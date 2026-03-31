// lib/ui/helb/helb_planner_screen.dart
//
// The HELB Semester Budget Planner.
//
// Tab 1 — Setup     : Enter HELB amount, semester dates, per-category allocations.
// Tab 2 — Overview  : Remaining balance, daily safe-to-spend, on-track status,
//                     PLUS "Days until HELB runs out" pace projection card.
// Tab 3 — Breakdown : Per-category progress bars with daily rate guidance.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:frontend/core/helb_storage.dart';
import 'package:frontend/data/local/secure_storage.dart';

// ── Top-level constants ───────────────────────────────────────────────────────
const List<String> _kCategories = [
  'Food', 'Transport', 'Entertainment', 'Shopping',
  'Health', 'Education', 'Utilities', 'Rent', 'Other',
];

const String _kApiBase = 'http://10.0.2.2:5000/api';
// ─────────────────────────────────────────────────────────────────────────────

class HelbPlannerScreen extends StatefulWidget {
  const HelbPlannerScreen({super.key});

  @override
  State<HelbPlannerScreen> createState() => _HelbPlannerScreenState();
}

class _HelbPlannerScreenState extends State<HelbPlannerScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  HelbPlan? _plan;
  bool _loading = true;

  Map<String, double> _categorySpent = {};
  double _totalSpent = 0.0;
  bool _expensesLoading = false;

  final _formKey = GlobalKey<FormState>();
  final _semesterNameCtrl = TextEditingController();
  final _helbAmountCtrl = TextEditingController();
  DateTime? _startDate;
  DateTime? _endDate;
  late final Map<String, TextEditingController> _allocCtrl;

  final _fmt = NumberFormat('#,##0.00', 'en_US');
  final _dateFmt = DateFormat('dd MMM yyyy');

  // ─────────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ─────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _allocCtrl = {
      for (final cat in _kCategories) cat: TextEditingController(),
    };
    _loadPlan();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _semesterNameCtrl.dispose();
    _helbAmountCtrl.dispose();
    for (final c in _allocCtrl.values) c.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Data loading
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _loadPlan() async {
    final plan = await HelbStorage.loadPlan();
    if (!mounted) return;
    setState(() {
      _plan = plan;
      _loading = false;
      if (plan != null) {
        _populateForm(plan);
        _tabController.animateTo(1);
      }
    });
    if (plan != null) _fetchSemesterExpenses(plan);
  }

  void _populateForm(HelbPlan plan) {
    _semesterNameCtrl.text = plan.semesterName;
    _helbAmountCtrl.text = plan.helbAmount.toStringAsFixed(0);
    _startDate = plan.startDate;
    _endDate = plan.endDate;
    for (final cat in _kCategories) {
      final alloc = plan.allocations[cat] ?? 0.0;
      _allocCtrl[cat]!.text = alloc > 0 ? alloc.toStringAsFixed(0) : '';
    }
  }

  Future<void> _fetchSemesterExpenses(HelbPlan plan) async {
    if (!mounted) return;
    setState(() => _expensesLoading = true);

    final token = await SecureStorage.getToken();
    if (token == null) {
      setState(() => _expensesLoading = false);
      return;
    }

    final Map<String, double> totals = {};
    final months = _monthsInRange(plan.startDate, plan.endDate);

    for (final ym in months) {
      try {
        final uri = Uri.parse(
          '$_kApiBase/expenses?month=${ym['month']}&year=${ym['year']}',
        );
        final response = await http.get(
          uri,
          headers: {'Authorization': 'Bearer $token'},
        );
        if (response.statusCode == 200) {
          final body = jsonDecode(response.body) as Map<String, dynamic>;
          final expenses = body['expenses'] as List<dynamic>;
          for (final e in expenses) {
            final dateAdded = DateTime.parse(e['date_added'] as String);
            if (!dateAdded.isBefore(plan.startDate) &&
                !dateAdded.isAfter(plan.endDate)) {
              final expenseType = e['expense_type'] as String;
              if (expenseType != 'one-time') {
                final category = e['category'] as String;
                final amount = (e['amount'] as num).toDouble();
                totals[category] = (totals[category] ?? 0.0) + amount;
              }
            }
          }
        }
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() {
      _categorySpent = totals;
      _totalSpent = totals.values.fold(0.0, (a, b) => a + b);
      _expensesLoading = false;
    });
  }

  List<Map<String, int>> _monthsInRange(DateTime start, DateTime end) {
    final months = <Map<String, int>>[];
    var y = start.year;
    var m = start.month;
    while (DateTime(y, m).compareTo(DateTime(end.year, end.month)) <= 0) {
      months.add({'year': y, 'month': m});
      m++;
      if (m > 12) { m = 1; y++; }
    }
    return months;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Setup tab actions
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _pickDate({required bool isStart}) async {
    final initial = isStart
        ? (_startDate ?? DateTime.now())
        : (_endDate ?? DateTime.now().add(const Duration(days: 120)));
    final first = isStart ? DateTime(2024) : (_startDate ?? DateTime(2024));

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: DateTime(2030),
    );
    if (picked != null && mounted) {
      setState(() {
        if (isStart) {
          _startDate = picked;
          if (_endDate != null && _endDate!.isBefore(picked)) _endDate = null;
        } else {
          _endDate = picked;
        }
      });
    }
  }

  void _applyEqualSplit() {
    final amount = double.tryParse(_helbAmountCtrl.text);
    if (amount == null || amount <= 0) {
      _showSnack('Enter your HELB amount first');
      return;
    }
    final perCat = (amount / _kCategories.length).floorToDouble();
    for (final cat in _kCategories) {
      _allocCtrl[cat]!.text = perCat.toStringAsFixed(0);
    }
    setState(() {});
  }

  void _apply503020() {
    final amount = double.tryParse(_helbAmountCtrl.text);
    if (amount == null || amount <= 0) {
      _showSnack('Enter your HELB amount first');
      return;
    }
    final needs = amount * 0.50;
    final wants = amount * 0.30;

    for (final cat in kHelbNeedsCategories) {
      _allocCtrl[cat]!.text =
          (needs / kHelbNeedsCategories.length).floorToDouble().toStringAsFixed(0);
    }
    for (final cat in kHelbWantsCategories) {
      _allocCtrl[cat]!.text =
          (wants / kHelbWantsCategories.length).floorToDouble().toStringAsFixed(0);
    }
    setState(() {});
  }

  Future<void> _savePlan() async {
    if (!_formKey.currentState!.validate()) return;
    if (_startDate == null || _endDate == null) {
      _showSnack('Please set both the start and end dates');
      return;
    }
    if (_endDate!.isBefore(_startDate!)) {
      _showSnack('End date must be after start date');
      return;
    }

    final allocations = <String, double>{};
    for (final cat in _kCategories) {
      final val = double.tryParse(_allocCtrl[cat]!.text);
      if (val != null && val > 0) allocations[cat] = val;
    }

    final plan = HelbPlan(
      semesterName: _semesterNameCtrl.text.trim(),
      helbAmount: double.parse(_helbAmountCtrl.text),
      startDate: _startDate!,
      endDate: _endDate!,
      allocations: allocations,
    );

    await HelbStorage.savePlan(plan);
    if (!mounted) return;
    setState(() => _plan = plan);
    _showSnack('Semester plan saved!', isSuccess: true);
    _fetchSemesterExpenses(plan);
    _tabController.animateTo(1);
  }

  Future<void> _deletePlan() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Plan'),
        content: const Text(
            'Delete your semester budget plan? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await HelbStorage.clearPlan();
      if (!mounted) return;
      setState(() {
        _plan = null;
        _categorySpent = {};
        _totalSpent = 0;
        _semesterNameCtrl.clear();
        _helbAmountCtrl.clear();
        _startDate = null;
        _endDate = null;
        for (final c in _allocCtrl.values) c.clear();
      });
      _tabController.animateTo(0);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Status helpers
  // ─────────────────────────────────────────────────────────────────────────

  String _statusLabel(double totalSpent, HelbPlan plan) {
    if (plan.daysElapsed == 0) return 'Not Started';
    final expected = plan.expectedSpentByNow;
    if (totalSpent <= expected * 0.85) return 'Ahead';
    if (totalSpent <= expected * 1.05) return 'On Track';
    if (totalSpent <= expected * 1.30) return 'Behind';
    return 'Critical';
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'Ahead':     return Colors.green.shade600;
      case 'On Track':  return Colors.teal.shade600;
      case 'Behind':    return Colors.orange.shade700;
      case 'Critical':  return Colors.red.shade600;
      default:          return Colors.blue.shade600;
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'Ahead':     return Icons.trending_up;
      case 'On Track':  return Icons.check_circle_outline;
      case 'Behind':    return Icons.warning_amber_outlined;
      case 'Critical':  return Icons.crisis_alert_outlined;
      default:          return Icons.hourglass_empty_outlined;
    }
  }

  IconData _categoryIcon(String category) {
    switch (category) {
      case 'Food':          return Icons.restaurant_outlined;
      case 'Transport':     return Icons.directions_bus_outlined;
      case 'Entertainment': return Icons.movie_outlined;
      case 'Shopping':      return Icons.shopping_bag_outlined;
      case 'Health':        return Icons.health_and_safety_outlined;
      case 'Education':     return Icons.menu_book_outlined;
      case 'Utilities':     return Icons.power_outlined;
      case 'Rent':          return Icons.home_outlined;
      default:              return Icons.category_outlined;
    }
  }

  void _showSnack(String msg, {bool isSuccess = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isSuccess ? Colors.green.shade700 : null,
    ));
  }

  double _allocationTotal() {
    return _kCategories.fold(0.0, (acc, cat) {
      return acc + (double.tryParse(_allocCtrl[cat]!.text) ?? 0.0);
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ★ NEW — Pace projection helpers
  // ─────────────────────────────────────────────────────────────────────────

  /// How many days the remaining balance will last at the current daily spend rate.
  /// Returns null if there is no spending data yet.
  int? _moneyLastsDays(HelbPlan plan) {
    if (_totalSpent <= 0 || plan.daysElapsed <= 0) return null;
    final dailyRate = _totalSpent / plan.daysElapsed;
    if (dailyRate <= 0) return null;
    final remaining =
        (plan.helbAmount - _totalSpent).clamp(0.0, double.infinity);
    return (remaining / dailyRate).floor();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('HELB Semester Planner'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.settings_outlined),  text: 'Setup'),
            Tab(icon: Icon(Icons.dashboard_outlined),  text: 'Overview'),
            Tab(icon: Icon(Icons.bar_chart_outlined),  text: 'Breakdown'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildSetupTab(),
          _buildOverviewTab(),
          _buildBreakdownTab(),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TAB 1 — SETUP
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildSetupTab() {
    final helbAmount      = double.tryParse(_helbAmountCtrl.text) ?? 0.0;
    final totalAllocated  = _allocationTotal();
    final unallocated     = helbAmount - totalAllocated;
    final isOverAllocated = unallocated < -0.01;

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionHeader(context, 'Semester Details'),
          const SizedBox(height: 10),

          TextFormField(
            controller: _semesterNameCtrl,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Semester Name',
              hintText: 'e.g. Semester 1 2025',
              prefixIcon: Icon(Icons.school_outlined),
              border: OutlineInputBorder(),
            ),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Required' : null,
          ),
          const SizedBox(height: 12),

          TextFormField(
            controller: _helbAmountCtrl,
            decoration: const InputDecoration(
              labelText: 'HELB / Lump-Sum Amount',
              prefixText: 'KES ',
              prefixIcon: Icon(Icons.account_balance_wallet_outlined),
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) => setState(() {}),
            validator: (v) {
              final n = double.tryParse(v ?? '');
              if (n == null || n <= 0) return 'Enter a valid amount';
              return null;
            },
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                  child: _dateTile(
                      label: 'Start Date', date: _startDate, isStart: true)),
              const SizedBox(width: 12),
              Expanded(
                  child: _dateTile(
                      label: 'End Date', date: _endDate, isStart: false)),
            ],
          ),

          if (_startDate != null &&
              _endDate != null &&
              !_endDate!.isBefore(_startDate!))
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '${_endDate!.difference(_startDate!).inDays} days  '
                '(${(_endDate!.difference(_startDate!).inDays / 30).toStringAsFixed(1)} months)',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.grey.shade600),
              ),
            ),

          const SizedBox(height: 24),
          _sectionHeader(context, 'Budget Allocations'),
          const SizedBox(height: 4),
          Text(
            'Divide your HELB across categories. '
            'Leave a category empty to skip it. '
            'Any unallocated amount becomes your implied savings.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Colors.grey.shade600),
          ),
          const SizedBox(height: 10),

          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _applyEqualSplit,
                  icon: const Icon(Icons.balance, size: 16),
                  label: const Text('Equal Split'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _apply503020,
                  icon: const Icon(Icons.pie_chart_outline, size: 16),
                  label: const Text('50/30/20'),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 12),
            child: Text(
              '50% Needs · 30% Wants · 20% implied savings',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey,
                    fontStyle: FontStyle.italic,
                  ),
            ),
          ),

          ..._kCategories.map((cat) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: TextFormField(
                controller: _allocCtrl[cat],
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: cat,
                  prefixText: 'KES ',
                  border: const OutlineInputBorder(),
                  prefixIcon: Icon(_categoryIcon(cat), size: 20),
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
            );
          }),

          const SizedBox(height: 4),
          _allocationSummaryBanner(
            helbAmount: helbAmount,
            totalAllocated: totalAllocated,
            unallocated: unallocated,
            isOverAllocated: isOverAllocated,
          ),
          const SizedBox(height: 20),

          ElevatedButton.icon(
            onPressed: _savePlan,
            icon: const Icon(Icons.save_outlined),
            label: Text(_plan == null ? 'Save Plan' : 'Update Plan'),
            style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(48)),
          ),

          if (_plan != null) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _deletePlan,
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              label: const Text('Delete Plan',
                  style: TextStyle(color: Colors.red)),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                side: const BorderSide(color: Colors.red),
              ),
            ),
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _dateTile({
    required String label,
    required DateTime? date,
    required bool isStart,
  }) {
    return InkWell(
      onTap: () => _pickDate(isStart: isStart),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade400),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.calendar_today_outlined, size: 16),
                const SizedBox(width: 6),
                Text(
                  date != null ? _dateFmt.format(date) : 'Tap to set',
                  style: TextStyle(
                    color: date != null ? null : Colors.grey,
                    fontWeight:
                        date != null ? FontWeight.w500 : FontWeight.normal,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _allocationSummaryBanner({
    required double helbAmount,
    required double totalAllocated,
    required double unallocated,
    required bool isOverAllocated,
  }) {
    final Color borderColor;
    final Color bgColor;
    if (isOverAllocated) {
      borderColor = Colors.red;
      bgColor = Colors.red.shade50;
    } else if (unallocated < 0.01) {
      borderColor = Colors.green;
      bgColor = Colors.green.shade50;
    } else {
      borderColor = Colors.blue.shade400;
      bgColor = Colors.blue.shade50;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Total Allocated',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              Text(
                'KES ${_fmt.format(totalAllocated)} / ${_fmt.format(helbAmount)}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isOverAllocated
                      ? Colors.red.shade700
                      : Colors.blue.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (isOverAllocated)
            Text(
              'Over-allocated by KES ${_fmt.format(unallocated.abs())} — reduce some categories.',
              style: TextStyle(fontSize: 12, color: Colors.red.shade700),
            )
          else if (unallocated > 0.01)
            Text(
              'KES ${_fmt.format(unallocated)} unallocated — this becomes your implied savings.',
              style: TextStyle(fontSize: 12, color: Colors.blue.shade700),
            )
          else
            Text(
              'Fully allocated. Every shilling has a job.',
              style: TextStyle(fontSize: 12, color: Colors.green.shade700),
            ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TAB 2 — OVERVIEW
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildOverviewTab() {
    if (_plan == null) {
      return _noDataPlaceholder(
        icon: Icons.calendar_month_outlined,
        message: 'No semester plan yet.\nGo to Setup to create one.',
      );
    }

    final plan = _plan!;
    final remaining =
        (plan.helbAmount - _totalSpent).clamp(0.0, double.infinity);
    final remainingPct = plan.helbAmount > 0
        ? (remaining / plan.helbAmount * 100).clamp(0.0, 100.0)
        : 0.0;
    final dailySafe =
        plan.daysRemaining > 0 ? remaining / plan.daysRemaining : 0.0;
    final status       = _statusLabel(_totalSpent, plan);
    final statusColor  = _statusColor(status);
    final daysProgress = plan.progressFraction.clamp(0.0, 1.0);

    return RefreshIndicator(
      onRefresh: () => _fetchSemesterExpenses(plan),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Semester name + date range
          Text(
            plan.semesterName,
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 2),
          Text(
            '${_dateFmt.format(plan.startDate)} — ${_dateFmt.format(plan.endDate)}',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Colors.grey),
          ),
          const SizedBox(height: 14),

          // ── Calendar days progress card ─────────────────────────────────
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Day ${plan.daysElapsed} of ${plan.totalDays}',
                          style:
                              const TextStyle(fontWeight: FontWeight.w600)),
                      Text(
                        '${plan.daysRemaining} days left',
                        style: TextStyle(
                          color: plan.daysRemaining < 14
                              ? Colors.orange.shade700
                              : Colors.grey,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: daysProgress,
                      minHeight: 10,
                      backgroundColor: Colors.grey.shade200,
                      valueColor: AlwaysStoppedAnimation(
                        daysProgress > 0.9
                            ? Colors.orange.shade600
                            : Colors.blue.shade500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${(daysProgress * 100).toStringAsFixed(0)}% of semester elapsed',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),

          // ── ★ NEW — Pace projection card ────────────────────────────────
          _buildPaceProjectionCard(plan),
          const SizedBox(height: 8),

          // Status chip
          Center(
            child: Chip(
              avatar: Icon(_statusIcon(status), color: statusColor, size: 18),
              label: Text(
                status,
                style: TextStyle(
                    color: statusColor, fontWeight: FontWeight.bold),
              ),
              backgroundColor: statusColor.withOpacity(0.1),
              side: BorderSide(color: statusColor.withOpacity(0.3)),
            ),
          ),
          const SizedBox(height: 10),

          // Remaining balance card
          Card(
            color: remainingPct > 30
                ? Colors.green.shade50
                : remainingPct > 10
                    ? Colors.orange.shade50
                    : Colors.red.shade50,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: remainingPct > 30
                    ? Colors.green.shade200
                    : remainingPct > 10
                        ? Colors.orange.shade200
                        : Colors.red.shade200,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  vertical: 20, horizontal: 16),
              child: Column(
                children: [
                  Text(
                    'Remaining Balance',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 6),
                  _expensesLoading
                      ? const SizedBox(
                          height: 36,
                          child: Center(
                              child: CircularProgressIndicator(
                                  strokeWidth: 2)),
                        )
                      : Text(
                          'KES ${_fmt.format(remaining)}',
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: remainingPct > 30
                                    ? Colors.green.shade700
                                    : remainingPct > 10
                                        ? Colors.orange.shade700
                                        : Colors.red.shade700,
                              ),
                        ),
                  const SizedBox(height: 4),
                  Text(
                    '${remainingPct.toStringAsFixed(1)}% of KES ${_fmt.format(plan.helbAmount)}',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Stats grid 2×2
          Row(
            children: [
              Expanded(
                child: _statCard(
                  label: 'Daily Safe-to-Spend',
                  value: 'KES ${_fmt.format(dailySafe)}',
                  icon: Icons.today_outlined,
                  color: Colors.blue.shade600,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _statCard(
                  label: 'Total Spent',
                  value: 'KES ${_fmt.format(_totalSpent)}',
                  icon: Icons.receipt_long_outlined,
                  color: Colors.orange.shade700,
                  isLoading: _expensesLoading,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _statCard(
                  label: 'Expected by Today',
                  value: 'KES ${_fmt.format(plan.expectedSpentByNow)}',
                  icon: Icons.schedule_outlined,
                  color: Colors.purple.shade500,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _statCard(
                  label: _totalSpent <= plan.expectedSpentByNow
                      ? 'Saved vs Pace'
                      : 'Over Pace By',
                  value: _totalSpent <= plan.expectedSpentByNow
                      ? 'KES ${_fmt.format(plan.expectedSpentByNow - _totalSpent)}'
                      : 'KES ${_fmt.format(_totalSpent - plan.expectedSpentByNow)}',
                  icon: Icons.compare_arrows_outlined,
                  color: _totalSpent <= plan.expectedSpentByNow
                      ? Colors.green.shade600
                      : Colors.red.shade600,
                  isLoading: _expensesLoading,
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => _tabController.animateTo(0),
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Edit Plan'),
            style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(44)),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ★ NEW — Pace projection card widget
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildPaceProjectionCard(HelbPlan plan) {
    final moneyDays = _moneyLastsDays(plan);

    // No spending yet — show a neutral placeholder
    if (_expensesLoading) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              const Icon(Icons.hourglass_empty_outlined,
                  size: 20, color: Colors.grey),
              const SizedBox(width: 10),
              Text('Calculating pace...',
                  style: TextStyle(color: Colors.grey.shade600)),
            ],
          ),
        ),
      );
    }

    if (moneyDays == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 20, color: Colors.grey.shade400),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'No spending recorded yet — pace projection will appear once you log expenses.',
                  style:
                      TextStyle(color: Colors.grey.shade500, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Compare money days vs calendar days remaining
    final calendarDaysLeft = plan.daysRemaining;
    final diff = moneyDays - calendarDaysLeft;

    final Color cardColor;
    final Color borderColor;
    final IconData icon;
    final String headline;
    final String subline;

    if (moneyDays <= 0) {
      // Money already gone
      cardColor   = Colors.red.shade50;
      borderColor = Colors.red.shade300;
      icon        = Icons.crisis_alert_outlined;
      headline    = 'HELB already depleted at this pace';
      subline     = 'Reduce spending immediately.';
    } else if (diff < -14) {
      // Money runs out more than 2 weeks before semester ends
      cardColor   = Colors.red.shade50;
      borderColor = Colors.red.shade300;
      icon        = Icons.crisis_alert_outlined;
      headline    = 'HELB runs out in ~$moneyDays days';
      subline     = '${diff.abs()} days before semester ends — critical overspend.';
    } else if (diff < 0) {
      // Money runs out slightly before semester ends
      cardColor   = Colors.orange.shade50;
      borderColor = Colors.orange.shade300;
      icon        = Icons.warning_amber_outlined;
      headline    = 'HELB runs out in ~$moneyDays days';
      subline     = '${diff.abs()} days short of semester end — reduce spending.';
    } else if (diff <= 14) {
      // Money just barely outlasts semester
      cardColor   = Colors.teal.shade50;
      borderColor = Colors.teal.shade300;
      icon        = Icons.check_circle_outline;
      headline    = 'HELB lasts ~$moneyDays more days';
      subline     = 'Outlasts semester by $diff days — stay disciplined.';
    } else {
      // Money comfortably outlasts semester
      cardColor   = Colors.green.shade50;
      borderColor = Colors.green.shade300;
      icon        = Icons.savings_outlined;
      headline    = 'HELB lasts ~$moneyDays more days';
      subline     = 'Outlasts semester by $diff days ✅ — excellent pace.';
    }

    // Daily spending rate for display
    final dailyRate = plan.daysElapsed > 0
        ? _totalSpent / plan.daysElapsed
        : 0.0;

    return Card(
      elevation: 0,
      color: cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(Icons.speed_outlined, size: 16, color: borderColor),
                const SizedBox(width: 6),
                Text(
                  'Spending Pace Projection',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Headline row
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 22, color: borderColor),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        headline,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: borderColor,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subline,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // Divider + daily rate footnote
            const SizedBox(height: 10),
            Divider(height: 1, color: borderColor.withOpacity(0.4)),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Current daily spend rate',
                  style: TextStyle(
                      fontSize: 12, color: Colors.grey.shade600),
                ),
                Text(
                  'KES ${_fmt.format(dailyRate)}/day',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statCard({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
    bool isLoading = false,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    label,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Colors.grey.shade600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            isLoading
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Text(
                    value,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TAB 3 — BREAKDOWN
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildBreakdownTab() {
    if (_plan == null) {
      return _noDataPlaceholder(
        icon: Icons.bar_chart_outlined,
        message: 'No semester plan yet.\nGo to Setup to create one.',
      );
    }

    final plan = _plan!;
    final allocated  = _kCategories
        .where((c) => (plan.allocations[c] ?? 0) > 0)
        .toList();
    final unallocated = _kCategories
        .where((c) => (plan.allocations[c] ?? 0) <= 0)
        .toList();

    return RefreshIndicator(
      onRefresh: () => _fetchSemesterExpenses(plan),
      child: _expensesLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  '${plan.semesterName} — Category Breakdown',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),

                if (allocated.isEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: [
                          Icon(Icons.pie_chart_outline,
                              size: 48,
                              color: Colors.grey.shade300),
                          const SizedBox(height: 12),
                          Text(
                            'No category allocations set.\nGo to Setup to allocate your budget.',
                            textAlign: TextAlign.center,
                            style:
                                TextStyle(color: Colors.grey.shade500),
                          ),
                        ],
                      ),
                    ),
                  )
                else ...[
                  ...allocated
                      .map((cat) => _buildCategoryBar(cat, plan))
                      .toList(),

                  if (unallocated.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _sectionHeader(context, 'Unallocated Categories'),
                    const SizedBox(height: 4),
                    Text(
                      'Spending in these categories is not tracked against a limit.',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Colors.grey),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: unallocated.map((cat) {
                        final spent = _categorySpent[cat] ?? 0;
                        return Chip(
                          avatar: Icon(_categoryIcon(cat), size: 14),
                          label: Text(
                            spent > 0
                                ? '$cat (KES ${_fmt.format(spent)})'
                                : cat,
                          ),
                          backgroundColor:
                              spent > 0 ? Colors.orange.shade50 : null,
                        );
                      }).toList(),
                    ),
                  ],
                ],
                const SizedBox(height: 32),
              ],
            ),
    );
  }

  Widget _buildCategoryBar(String category, HelbPlan plan) {
    final allocated = plan.allocations[category] ?? 0.0;
    final spent     = _categorySpent[category] ?? 0.0;
    final progress  =
        allocated > 0 ? (spent / allocated).clamp(0.0, 1.5) : 0.0;
    final isOver = spent > allocated;
    final isNear = !isOver && progress > 0.8;

    final Color barColor;
    final String statusLabel;
    if (isOver) {
      barColor    = Colors.red.shade600;
      statusLabel = 'Over Budget';
    } else if (isNear) {
      barColor    = Colors.orange.shade600;
      statusLabel = 'Near Limit';
    } else {
      barColor    = Colors.green.shade600;
      statusLabel = 'On Track';
    }

    final remaining   = (allocated - spent).clamp(0.0, double.infinity);
    final daysLeft    = plan.daysRemaining;
    final dailyNeeded =
        (daysLeft > 0 && remaining > 0) ? remaining / daysLeft : 0.0;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_categoryIcon(category), size: 20, color: barColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    category,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: barColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: barColor.withOpacity(0.4)),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                        fontSize: 11,
                        color: barColor,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress.clamp(0.0, 1.0),
                minHeight: 8,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation(barColor),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'KES ${_fmt.format(spent)} of ${_fmt.format(allocated)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Text(
                  '${(progress * 100).clamp(0, 150).toStringAsFixed(0)}%',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: barColor),
                ),
              ],
            ),
            if (!isOver && daysLeft > 0 && remaining > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Budget: KES ${_fmt.format(dailyNeeded)}/day for $daysLeft days',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.grey.shade600),
                ),
              ),
            if (isOver)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Overspent by KES ${_fmt.format(spent - allocated)}',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.red.shade700),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Shared helpers
  // ─────────────────────────────────────────────────────────────────────────

  Widget _noDataPlaceholder({
    required IconData icon,
    required String message,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 72, color: Colors.grey.shade200),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style:
                  TextStyle(color: Colors.grey.shade500, fontSize: 15),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: () => _tabController.animateTo(0),
              icon: const Icon(Icons.add),
              label: const Text('Set Up Plan'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.primary,
          ),
    );
  }
}