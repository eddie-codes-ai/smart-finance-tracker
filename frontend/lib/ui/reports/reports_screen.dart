// lib/ui/reports/reports_screen.dart
// UPDATED: Full dark mode support.

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
  final List<Map<String, dynamic>> _monthlyData = [];
  bool _monthlyLoading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.index == 1 && _monthlyData.isEmpty) _loadMonthlyData();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadCurrent());
  }

  @override
  void dispose() { _tabController.dispose(); super.dispose(); }

  Future<void> _loadCurrent() async {
    if (_initialLoadDone) return;
    _initialLoadDone = true;
    final now = DateTime.now();
    await Future.wait([
      context.read<ExpenseProvider>().fetchExpenses(month: now.month, year: now.year),
      context.read<IncomeProvider>().fetchIncome(month: now.month, year: now.year),
    ]);
  }

  Future<void> _loadMonthlyData() async {
    setState(() => _monthlyLoading = true);
    final now = DateTime.now();
    final List<Map<String, dynamic>> data = [];
    for (int i = 5; i >= 0; i--) {
      int m = now.month - i; int y = now.year;
      while (m <= 0) { m += 12; y -= 1; }
      final incProvider = context.read<IncomeProvider>();
      final expProvider = context.read<ExpenseProvider>();
      await incProvider.fetchIncome(month: m, year: y);
      await expProvider.fetchExpenses(month: m, year: y);
      data.add({'label': DateFormat('MMM').format(DateTime(y, m)), 'income': incProvider.total, 'expenses': expProvider.total});
    }
    final curInc = context.read<IncomeProvider>();
    final curExp = context.read<ExpenseProvider>();
    final now2 = DateTime.now();
    await Future.wait([
      curInc.fetchIncome(month: now2.month, year: now2.year),
      curExp.fetchExpenses(month: now2.month, year: now2.year),
    ]);
    if (mounted) setState(() { _monthlyData..clear()..addAll(data); _monthlyLoading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        Container(
          color: cs.surface,
          child: TabBar(
            controller: _tabController,
            labelColor: AppTheme.primary,
            unselectedLabelColor: cs.onSurface.withOpacity(0.5),
            indicatorColor: AppTheme.primary,
            tabs: const [
              Tab(icon: Icon(Icons.pie_chart_outline, size: 18), text: 'Expenses'),
              Tab(icon: Icon(Icons.bar_chart_outlined, size: 18), text: 'Monthly'),
            ],
          ),
        ),
        Expanded(child: TabBarView(controller: _tabController,
            children: [_buildPieTab(), _buildBarTab()])),
      ],
    );
  }

  Widget _buildPieTab() {
    final expense = context.watch<ExpenseProvider>();
    final cs = Theme.of(context).colorScheme;
    if (expense.isLoading) return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
    final totals = expense.categoryTotals;
    if (totals.isEmpty) return _buildEmptyState('No expenses recorded this month.', Icons.pie_chart_outline);
    final entries = totals.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final total = entries.fold<double>(0, (s, e) => s + e.value);
    final fmt = NumberFormat('#,##0.00', 'en_US');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Text('Expense Distribution — ${DateFormat('MMMM yyyy').format(DateTime.now())}',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface),
              textAlign: TextAlign.center),
          const SizedBox(height: 24),
          SizedBox(
            height: 240,
            child: PieChart(PieChartData(
              pieTouchData: PieTouchData(touchCallback: (event, response) {
                setState(() {
                  if (!event.isInterestedForInteractions || response == null || response.touchedSection == null) {
                    _touchedPieIndex = -1; return;
                  }
                  _touchedPieIndex = response.touchedSection!.touchedSectionIndex;
                });
              }),
              sections: entries.asMap().entries.map((entry) {
                final i = entry.key; final cat = entry.value.key; final val = entry.value.value;
                final isTouched = i == _touchedPieIndex;
                final pct = (val / total * 100);
                final color = AppTheme.categoryColor(i);
                return PieChartSectionData(
                  value: val, color: color,
                  radius: isTouched ? 90 : 75,
                  title: isTouched ? '${pct.toStringAsFixed(1)}%' : pct >= 8 ? '${pct.toStringAsFixed(0)}%' : '',
                  titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white),
                  badgeWidget: isTouched ? Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(8),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 6)]),
                    child: Text(cat, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
                  ) : null,
                  badgePositionPercentageOffset: 1.3,
                );
              }).toList(),
              centerSpaceRadius: 48, sectionsSpace: 2,
            )),
          ),
          const SizedBox(height: 24),
          ...entries.asMap().entries.map((entry) {
            final i = entry.key; final cat = entry.value.key; final val = entry.value.value;
            final pct = (val / total * 100);
            final color = AppTheme.categoryColor(i);
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(10)),
              child: Row(
                children: [
                  Container(width: 12, height: 12, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
                  const SizedBox(width: 10),
                  Expanded(child: Text(cat, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurface))),
                  Text('${AppConstants.currency} ${fmt.format(val)}',
                      style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(0.6))),
                  const SizedBox(width: 8),
                  SizedBox(width: 44,
                      child: Text('${pct.toStringAsFixed(1)}%', textAlign: TextAlign.right,
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color))),
                ],
              ),
            );
          }),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(color: AppTheme.error.withOpacity(0.08), borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.error.withOpacity(0.2))),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('Total Expenses', style: TextStyle(fontWeight: FontWeight.w700, color: cs.onSurface)),
              Text('${AppConstants.currency} ${fmt.format(total)}',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppTheme.error)),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _buildBarTab() {
    final cs = Theme.of(context).colorScheme;
    if (_monthlyLoading) {
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const CircularProgressIndicator(color: AppTheme.primary), const SizedBox(height: 16),
        Text('Loading 6-month history...', style: TextStyle(color: cs.onSurface.withOpacity(0.6))),
      ]));
    }
    if (_monthlyData.isEmpty) return _buildEmptyState('No historical data available yet.', Icons.bar_chart_outlined);

    final fmt = NumberFormat('#,##0', 'en_US');
    final allValues = _monthlyData.expand((m) => [m['income'] as double, m['expenses'] as double]).toList();
    final maxY = (allValues.reduce((a, b) => a > b ? a : b) * 1.2).ceilToDouble();
    final gridLineColor = Theme.of(context).dividerColor;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Income vs Expenses — Last 6 Months',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface),
              textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _legendDot(AppTheme.success, 'Income'), const SizedBox(width: 20),
            _legendDot(AppTheme.error, 'Expenses'),
          ]),
          const SizedBox(height: 20),
          SizedBox(
            height: 260,
            child: BarChart(BarChartData(
              maxY: maxY > 0 ? maxY : 10000,
              barTouchData: BarTouchData(touchTooltipData: BarTouchTooltipData(
                getTooltipItem: (group, groupIndex, rod, rodIndex) {
                  final m = _monthlyData[groupIndex];
                  final isIncome = rodIndex == 0;
                  final val = isIncome ? m['income'] : m['expenses'];
                  return BarTooltipItem('${isIncome ? 'Income' : 'Expenses'}\n${AppConstants.currency} ${fmt.format(val)}',
                      TextStyle(color: isIncome ? AppTheme.success : AppTheme.error, fontWeight: FontWeight.w700, fontSize: 12));
                },
              )),
              titlesData: FlTitlesData(
                bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true,
                    getTitlesWidget: (value, meta) {
                      final i = value.toInt();
                      if (i < 0 || i >= _monthlyData.length) return const SizedBox.shrink();
                      return Padding(padding: const EdgeInsets.only(top: 6),
                          child: Text(_monthlyData[i]['label'] as String,
                              style: TextStyle(fontSize: 11, color: cs.onSurface.withOpacity(0.6))));
                    }, reservedSize: 28)),
                leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 52,
                    getTitlesWidget: (value, meta) => Text(
                        value >= 1000 ? '${(value / 1000).toStringAsFixed(0)}K' : value.toStringAsFixed(0),
                        style: TextStyle(fontSize: 10, color: cs.onSurface.withOpacity(0.6))))),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              gridData: FlGridData(drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) => FlLine(color: gridLineColor, strokeWidth: 1)),
              borderData: FlBorderData(show: false),
              barGroups: _monthlyData.asMap().entries.map((entry) {
                final i = entry.key; final m = entry.value;
                return BarChartGroupData(x: i, barRods: [
                  BarChartRodData(toY: (m['income'] as double).clamp(0, maxY), color: AppTheme.success,
                      width: 14, borderRadius: const BorderRadius.vertical(top: Radius.circular(4))),
                  BarChartRodData(toY: (m['expenses'] as double).clamp(0, maxY), color: AppTheme.error,
                      width: 14, borderRadius: const BorderRadius.vertical(top: Radius.circular(4))),
                ], barsSpace: 4);
              }).toList(),
            )),
          ),
          const SizedBox(height: 24),
          Text('Monthly Summary', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: cs.onSurface)),
          const SizedBox(height: 10),
          ..._monthlyData.reversed.map((m) {
            final income = m['income'] as double;
            final expenses = m['expenses'] as double;
            final savings = income - expenses;
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(10)),
              child: Row(
                children: [
                  SizedBox(width: 36,
                      child: Text(m['label'] as String,
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: cs.onSurface))),
                  const SizedBox(width: 8),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _tableRow('In', '${AppConstants.currency} ${fmt.format(income)}', AppTheme.success),
                    _tableRow('Out', '${AppConstants.currency} ${fmt.format(expenses)}', AppTheme.error),
                  ])),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text('Saved', style: TextStyle(fontSize: 10, color: cs.onSurface.withOpacity(0.6))),
                    Text('${AppConstants.currency} ${fmt.format(savings)}',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                            color: savings >= 0 ? AppTheme.success : AppTheme.error)),
                  ]),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(children: [
      Container(width: 12, height: 12, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
      const SizedBox(width: 6),
      Text(label, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6))),
    ]);
  }

  Widget _tableRow(String label, String value, Color color) {
    return Row(children: [
      Text('$label  ', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6))),
      Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
    ]);
  }

  Widget _buildEmptyState(String message, IconData icon) {
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(icon, size: 52, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4)),
      const SizedBox(height: 12),
      Text(message, textAlign: TextAlign.center,
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6))),
    ]));
  }
}