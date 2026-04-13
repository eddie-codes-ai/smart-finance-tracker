// lib/ui/budget/budget_screen.dart
// UPDATED: Full dark mode support.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../core/constants.dart';
import '../../core/routes.dart';
import '../../providers/budget_provider.dart';
import '../../providers/expense_provider.dart';

class BudgetScreen extends StatefulWidget {
  const BudgetScreen({super.key});
  @override
  State<BudgetScreen> createState() => _BudgetScreenState();
}

class _BudgetScreenState extends State<BudgetScreen> {
  bool _initialLoadDone = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  Future<void> _loadData() async {
    if (_initialLoadDone) return;
    _initialLoadDone = true;
    final now = DateTime.now();
    final monthYear = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    await Future.wait([
      context.read<BudgetProvider>().fetchBudgets(monthYear: monthYear),
      context.read<ExpenseProvider>().fetchExpenses(month: now.month, year: now.year),
    ]);
  }

  Future<void> _refresh() async {
    _initialLoadDone = false;
    await _loadData();
  }

  @override
  Widget build(BuildContext context) {
    final budget = context.watch<BudgetProvider>();
    final expense = context.watch<ExpenseProvider>();
    final fmt = NumberFormat('#,##0.00', 'en_US');
    final categoryTotals = expense.categoryTotals;

    return RefreshIndicator(
      onRefresh: _refresh,
      color: AppTheme.primary,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: _buildSummaryHeader(budget, categoryTotals, fmt)),
          if (budget.isLoading)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator(color: AppTheme.primary)),
            )
          else if (budget.budgets.isEmpty)
            SliverFillRemaining(child: _buildEmptyState())
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final b = budget.budgets[index];
                    final spent = categoryTotals[b.category] ?? 0.0;
                    return _buildBudgetCard(category: b.category, limit: b.limit, spent: spent, fmt: fmt);
                  },
                  childCount: budget.budgets.length,
                ),
              ),
            ),
          if (!budget.isLoading && categoryTotals.isNotEmpty)
            SliverToBoxAdapter(child: _buildUnbudgetedSection(budget, categoryTotals, fmt)),
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }

  // ─── Summary Header (always primary-colored — no dark mode change needed) ─
  Widget _buildSummaryHeader(BudgetProvider budget, Map<String, double> categoryTotals, NumberFormat fmt) {
    final totalBudgeted = budget.budgets.fold<double>(0, (sum, b) => sum + b.limit);
    final totalSpent    = budget.budgets.fold<double>(0, (sum, b) => sum + (categoryTotals[b.category] ?? 0));
    final remaining     = totalBudgeted - totalSpent;
    final usagePercent  = totalBudgeted > 0 ? (totalSpent / totalBudgeted) : 0.0;

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: AppTheme.primary, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Monthly Budget Overview', style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _headerStat(label: 'Budgeted',
                  value: '${AppConstants.currency} ${fmt.format(totalBudgeted)}', color: Colors.white),
              _headerStat(label: 'Spent',
                  value: '${AppConstants.currency} ${fmt.format(totalSpent)}', color: Colors.white70),
              _headerStat(label: 'Remaining',
                  value: '${AppConstants.currency} ${fmt.format(remaining)}',
                  color: remaining >= 0 ? Colors.greenAccent : Colors.redAccent),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: usagePercent.clamp(0.0, 1.0),
              backgroundColor: Colors.white24,
              valueColor: AlwaysStoppedAnimation<Color>(
                usagePercent > 1.0 ? Colors.redAccent : usagePercent > 0.8 ? Colors.orangeAccent : Colors.greenAccent),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 6),
          Text('${(usagePercent * 100).clamp(0, 999).toStringAsFixed(1)}% of total budget used',
              style: const TextStyle(color: Colors.white60, fontSize: 11)),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => Navigator.pushNamed(context, AppRoutes.addBudget).then((_) => _refresh()),
              icon: const Icon(Icons.add, size: 16, color: Colors.white),
              label: const Text('Set / Update a Budget', style: TextStyle(color: Colors.white)),
              style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.white38),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerStat({required String label, required String value, required Color color}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text(' ', style: TextStyle(color: Colors.white54, fontSize: 11)), // spacer trick kept
      Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
      const SizedBox(height: 2),
      Text(value, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w700)),
    ]);
  }

  // ─── Budget Card ──────────────────────────────────────────────────────────
  Widget _buildBudgetCard({
    required String category, required double limit,
    required double spent, required NumberFormat fmt,
  }) {
    final cs = Theme.of(context).colorScheme;
    final percent   = limit > 0 ? (spent / limit) : 0.0;
    final isOver    = spent > limit;
    final remaining = limit - spent;

    Color barColor;
    if (isOver)          barColor = AppTheme.error;
    else if (percent > 0.8) barColor = AppTheme.warning;
    else                 barColor = AppTheme.success;

    return GestureDetector(
      onTap: () => Navigator.pushNamed(context, AppRoutes.addBudget,
          arguments: {'category': category, 'currentLimit': limit}).then((_) => _refresh()),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(12),
          border: isOver ? Border.all(color: AppTheme.error.withOpacity(0.4)) : null,
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(color: barColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                    child: Icon(_categoryIcon(category), size: 16, color: barColor),
                  ),
                  const SizedBox(width: 10),
                  Text(category, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: cs.onSurface)),
                ]),
                Icon(Icons.edit_outlined, size: 14, color: cs.onSurface.withOpacity(0.5)),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: percent.clamp(0.0, 1.0),
                backgroundColor: Theme.of(context).dividerColor,
                valueColor: AlwaysStoppedAnimation<Color>(barColor),
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${AppConstants.currency} ${fmt.format(spent)} of ${fmt.format(limit)}',
                    style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.6))),
                Text(
                  isOver
                      ? 'Over by ${AppConstants.currency} ${fmt.format(spent - limit)}'
                      : '${AppConstants.currency} ${fmt.format(remaining)} left',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                      color: isOver ? AppTheme.error : AppTheme.success),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text('${(percent * 100).clamp(0, 999).toStringAsFixed(1)}% used',
                style: TextStyle(fontSize: 11, color: isOver ? AppTheme.error : cs.onSurface.withOpacity(0.5))),
          ],
        ),
      ),
    );
  }

  // ─── Unbudgeted Categories ────────────────────────────────────────────────
  Widget _buildUnbudgetedSection(BudgetProvider budget, Map<String, double> categoryTotals, NumberFormat fmt) {
    final cs = Theme.of(context).colorScheme;
    final budgetedCategories = budget.budgets.map((b) => b.category).toSet();
    final unbudgeted = categoryTotals.entries.where((e) => !budgetedCategories.contains(e.key)).toList();
    if (unbudgeted.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text('Spending Without a Budget',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: cs.onSurface.withOpacity(0.6))),
          ),
          ...unbudgeted.map((e) => Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: cs.surface, borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.warning.withOpacity(0.4)),
            ),
            child: Row(children: [
              Icon(_categoryIcon(e.key), size: 18, color: AppTheme.warning),
              const SizedBox(width: 12),
              Expanded(child: Text(e.key, style: TextStyle(fontWeight: FontWeight.w600, color: cs.onSurface))),
              Text('${AppConstants.currency} ${fmt.format(e.value)}',
                  style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.warning)),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => Navigator.pushNamed(context, AppRoutes.addBudget,
                    arguments: {'category': e.key}).then((_) => _refresh()),
                child: const Icon(Icons.add_circle_outline, size: 20, color: AppTheme.primary),
              ),
            ]),
          )),
        ],
      ),
    );
  }

  // ─── Empty State ──────────────────────────────────────────────────────────
  Widget _buildEmptyState() {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.pie_chart_outline, size: 52, color: cs.onSurface.withOpacity(0.4)),
        const SizedBox(height: 12),
        Text('No budgets set yet.', style: TextStyle(fontWeight: FontWeight.w600, color: cs.onSurface)),
        const SizedBox(height: 6),
        Text('Tap the button above to set spending\nlimits for each category.',
            textAlign: TextAlign.center, style: TextStyle(color: cs.onSurface.withOpacity(0.6))),
        const SizedBox(height: 20),
        ElevatedButton.icon(
          onPressed: () => Navigator.pushNamed(context, AppRoutes.addBudget).then((_) => _refresh()),
          icon: const Icon(Icons.add), label: const Text('Set Your First Budget'),
        ),
      ]),
    );
  }

  IconData _categoryIcon(String category) {
    switch (category) {
      case 'Food':          return Icons.restaurant_outlined;
      case 'Transport':     return Icons.directions_bus_outlined;
      case 'Entertainment': return Icons.movie_outlined;
      case 'Shopping':      return Icons.shopping_bag_outlined;
      case 'Health':        return Icons.local_hospital_outlined;
      case 'Education':     return Icons.school_outlined;
      case 'Utilities':     return Icons.bolt_outlined;
      case 'Rent':          return Icons.home_outlined;
      default:              return Icons.category_outlined;
    }
  }
}