// lib/ui/reports/reports_screen.dart
// Visual reporting screen.
// Tab 1 — Pie Chart: expense distribution by category for the current month.
// Tab 2 — Bar Chart: income vs expenses comparison across the last 6 months.
// Uses fl_chart library for both charts.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../core/constants.dart';
import '../../providers/expense_provider.dart';
import '../../providers/income_provider.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _initialLoadDone = false;
  int _touchedPieIndex = -1;

  // Last 6 months of data for bar chart.
  // Each entry: { 'label': 'Jan', 'income': x, 'expenses': y }
  final List<Map<String, dynamic>> _monthlyData = [];
  bool _monthlyLoading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.index == 1 && _monthlyData.isEmpty) {
        _loadMonthlyData();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadCurrent());
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrent() async {
    if (_initialLoadDone) return;
    _initialLoadDone = true;
    final now = DateTime.now();
    await Future.wait([
      context.read<ExpenseProvider>().fetchExpenses(
            month: now.month, year: now.year),
      context.read<IncomeProvider>().fetchIncome(
            month: now.month, year: now.year),
    ]);
  }

  // Fetches income + expense totals for the last 6 months individually.
  Future<void> _loadMonthlyData() async {
    setState(() => _monthlyLoading = true);
    final now = DateTime.now();
    final List<Map<String, dynamic>> data = [];

    for (int i = 5; i >= 0; i--) {
      int m = now.month - i;
      int y = now.year;
      while (m <= 0) {
        m += 12;
        y -= 1;
      }

      final incProvider = context.read<IncomeProvider>();
      final expProvider = context.read<ExpenseProvider>();

      // Fetch sequentially to avoid provider conflicts.
      await incProvider.fetchIncome(month: m, year: y);
      await expProvider.fetchExpenses(month: m, year: y);

      data.add({
        'label': DateFormat('MMM').format(DateTime(y, m)),
        'income': incProvider.total,
        'expenses': expProvider.total,
      });
    }

    // Restore current month after pulling history.
    final curInc = context.read<IncomeProvider>();
    final curExp = context.read<ExpenseProvider>();
    await Future.wait([
      curInc.fetchIncome(month: now.month, year: now.year),
      curExp.fetchExpenses(month: now.month, year: now.year),
    ]);

    if (mounted) {
      setState(() {
        _monthlyData
          ..clear()
          ..addAll(data);
        _monthlyLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          color: AppTheme.surface,
          child: TabBar(
            controller: _tabController,
            labelColor: AppTheme.primary,
            unselectedLabelColor: AppTheme.textSecondary,
            indicatorColor: AppTheme.primary,
            tabs: const [
              Tab(
                icon: Icon(Icons.pie_chart_outline, size: 18),
                text: 'Expenses',
              ),
              Tab(
                icon: Icon(Icons.bar_chart_outlined, size: 18),
                text: 'Monthly',
              ),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildPieTab(),
              _buildBarTab(),
            ],
          ),
        ),
      ],
    );
  }

  // ─── Pie Chart Tab ────────────────────────────────────────────────────────
  Widget _buildPieTab() {
    final expense = context.watch<ExpenseProvider>();

    if (expense.isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: AppTheme.primary));
    }

    final totals = expense.categoryTotals;
    if (totals.isEmpty) {
      return _buildEmptyState(
          'No expenses recorded this month.',
          Icons.pie_chart_outline);
    }

    final entries = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = entries.fold<double>(0, (s, e) => s + e.value);
    final fmt = NumberFormat('#,##0.00', 'en_US');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Month label
          Text(
            'Expense Distribution — ${DateFormat('MMMM yyyy').format(DateTime.now())}',
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),

          // Pie chart
          SizedBox(
            height: 240,
            child: PieChart(
              PieChartData(
                pieTouchData: PieTouchData(
                  touchCallback: (event, response) {
                    setState(() {
                      if (!event.isInterestedForInteractions ||
                          response == null ||
                          response.touchedSection == null) {
                        _touchedPieIndex = -1;
                        return;
                      }
                      _touchedPieIndex =
                          response.touchedSection!.touchedSectionIndex;
                    });
                  },
                ),
                sections: entries.asMap().entries.map((entry) {
                  final i = entry.key;
                  final cat = entry.value.key;
                  final val = entry.value.value;
                  final isTouched = i == _touchedPieIndex;
                  final pct = (val / total * 100);
                  final color = AppTheme.categoryColor(i);

                  return PieChartSectionData(
                    value: val,
                    color: color,
                    radius: isTouched ? 90 : 75,
                    title: isTouched
                        ? '${pct.toStringAsFixed(1)}%'
                        : pct >= 8
                            ? '${pct.toStringAsFixed(0)}%'
                            : '',
                    titleStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                    badgeWidget: isTouched
                        ? Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.15),
                                  blurRadius: 6,
                                )
                              ],
                            ),
                            child: Text(
                              cat,
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: color),
                            ),
                          )
                        : null,
                    badgePositionPercentageOffset: 1.3,
                  );
                }).toList(),
                centerSpaceRadius: 48,
                sectionsSpace: 2,
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Legend
          ...entries.asMap().entries.map((entry) {
            final i = entry.key;
            final cat = entry.value.key;
            final val = entry.value.value;
            final pct = (val / total * 100);
            final color = AppTheme.categoryColor(i);

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(3)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(cat,
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary)),
                  ),
                  Text(
                    '${AppConstants.currency} ${fmt.format(val)}',
                    style: const TextStyle(
                        fontSize: 13, color: AppTheme.textSecondary),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 44,
                    child: Text(
                      '${pct.toStringAsFixed(1)}%',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: color),
                    ),
                  ),
                ],
              ),
            );
          }),

          const SizedBox(height: 12),

          // Total row
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.error.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: AppTheme.error.withOpacity(0.2)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total Expenses',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary)),
                Text(
                  '${AppConstants.currency} ${fmt.format(total)}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: AppTheme.error),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Bar Chart Tab ────────────────────────────────────────────────────────
  Widget _buildBarTab() {
    if (_monthlyLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: AppTheme.primary),
            SizedBox(height: 16),
            Text('Loading 6-month history...',
                style: TextStyle(color: AppTheme.textSecondary)),
          ],
        ),
      );
    }

    if (_monthlyData.isEmpty) {
      return _buildEmptyState(
          'No historical data available yet.', Icons.bar_chart_outlined);
    }

    final fmt = NumberFormat('#,##0', 'en_US');
    final allValues = _monthlyData
        .expand((m) => [m['income'] as double, m['expenses'] as double])
        .toList();
    final maxY = (allValues.reduce((a, b) => a > b ? a : b) * 1.2)
        .ceilToDouble();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Income vs Expenses — Last 6 Months',
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),

          // Legend
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _legendDot(AppTheme.success, 'Income'),
              const SizedBox(width: 20),
              _legendDot(AppTheme.error, 'Expenses'),
            ],
          ),

          const SizedBox(height: 20),

          // Bar chart
          SizedBox(
            height: 260,
            child: BarChart(
              BarChartData(
                maxY: maxY > 0 ? maxY : 10000,
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final m = _monthlyData[groupIndex];
                      final isIncome = rodIndex == 0;
                      final val =
                          isIncome ? m['income'] : m['expenses'];
                      return BarTooltipItem(
                        '${isIncome ? 'Income' : 'Expenses'}\n${AppConstants.currency} ${fmt.format(val)}',
                        TextStyle(
                          color: isIncome
                              ? AppTheme.success
                              : AppTheme.error,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      );
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        final i = value.toInt();
                        if (i < 0 || i >= _monthlyData.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            _monthlyData[i]['label'] as String,
                            style: const TextStyle(
                                fontSize: 11,
                                color: AppTheme.textSecondary),
                          ),
                        );
                      },
                      reservedSize: 28,
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 52,
                      getTitlesWidget: (value, meta) => Text(
                        value >= 1000
                            ? '${(value / 1000).toStringAsFixed(0)}K'
                            : value.toStringAsFixed(0),
                        style: const TextStyle(
                            fontSize: 10,
                            color: AppTheme.textSecondary),
                      ),
                    ),
                  ),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                ),
                gridData: FlGridData(
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: AppTheme.divider,
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                barGroups: _monthlyData.asMap().entries.map((entry) {
                  final i = entry.key;
                  final m = entry.value;
                  return BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: (m['income'] as double).clamp(0, maxY),
                        color: AppTheme.success,
                        width: 14,
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4)),
                      ),
                      BarChartRodData(
                        toY: (m['expenses'] as double).clamp(0, maxY),
                        color: AppTheme.error,
                        width: 14,
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4)),
                      ),
                    ],
                    barsSpace: 4,
                  );
                }).toList(),
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Monthly summary table
          const Text(
            'Monthly Summary',
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 10),
          ..._monthlyData.reversed.map((m) {
            final income = m['income'] as double;
            final expenses = m['expenses'] as double;
            final savings = income - expenses;
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 36,
                    child: Text(
                      m['label'] as String,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: AppTheme.textPrimary),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _tableRow('In',
                            '${AppConstants.currency} ${fmt.format(income)}',
                            AppTheme.success),
                        _tableRow('Out',
                            '${AppConstants.currency} ${fmt.format(expenses)}',
                            AppTheme.error),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text('Saved',
                          style: TextStyle(
                              fontSize: 10,
                              color: AppTheme.textSecondary)),
                      Text(
                        '${AppConstants.currency} ${fmt.format(savings)}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: savings >= 0
                              ? AppTheme.success
                              : AppTheme.error,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────
  Widget _legendDot(Color color, String label) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
              color: color, borderRadius: BorderRadius.circular(3)),
        ),
        const SizedBox(width: 6),
        Text(label,
            style: const TextStyle(
                fontSize: 12, color: AppTheme.textSecondary)),
      ],
    );
  }

  Widget _tableRow(String label, String value, Color color) {
    return Row(
      children: [
        Text('$label  ',
            style: const TextStyle(
                fontSize: 11, color: AppTheme.textSecondary)),
        Text(value,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color)),
      ],
    );
  }

  Widget _buildEmptyState(String message, IconData icon) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 52, color: AppTheme.textSecondary),
          const SizedBox(height: 12),
          Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.textSecondary)),
        ],
      ),
    );
  }
}