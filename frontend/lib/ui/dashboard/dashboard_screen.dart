// lib/ui/dashboard/dashboard_screen.dart
// UPDATED: Full dark mode support.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../core/routes.dart';
import '../../core/constants.dart';
import '../../providers/auth_provider.dart';
import '../../providers/analysis_provider.dart';
import '../../providers/income_provider.dart';
import '../../providers/expense_provider.dart';
import '../../models/analysis_result_model.dart';
import '../helb/helb_banner_widget.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
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
    await Future.wait([
      context.read<AnalysisProvider>().analyze(month: now.month, year: now.year),
      context.read<IncomeProvider>().fetchIncome(month: now.month, year: now.year),
      context.read<ExpenseProvider>().fetchExpenses(month: now.month, year: now.year),
    ]);
  }

  Future<void> _refresh() async {
    _initialLoadDone = false;
    await _loadData();
  }

  @override
  Widget build(BuildContext context) {
    final auth     = context.watch<AuthProvider>();
    final analysis = context.watch<AnalysisProvider>();
    final income   = context.watch<IncomeProvider>();
    final expense  = context.watch<ExpenseProvider>();
    final hasIncome   = income.total > 0;
    final hasExpenses = expense.total > 0;
    final hasScore    = analysis.hasResult;
    final isNewUser   = !hasIncome && !hasExpenses && !hasScore;
    final goalHealth     = analysis.hasResult ? analysis.result!.goalHealth : '';
    final noGoalSet      = goalHealth == 'No savings goal set.';
    final showGoalBanner = analysis.hasResult;
    final double balance = analysis.hasResult
        ? analysis.result!.balance
        : income.total - expense.total;

    return RefreshIndicator(
      onRefresh: _refresh,
      color: AppTheme.primary,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildGreeting(auth.user?.username ?? 'Student'),
            if (analysis.isLoading) _buildScoreCardSkeleton()
            else if (hasScore) _buildScoreCard(analysis.result!)
            else _buildScoreCardEmpty(),
            const SizedBox(height: 16),
            _buildSummaryRow(income: income.total, expenses: expense.total, balance: balance),
            const SizedBox(height: 20),
            if (isNewUser) _buildOnboardingChecklist(),
            if (showGoalBanner) ...[_buildGoalBanner(goalHealth, noGoalSet), const SizedBox(height: 12)],
            const HelbBannerWidget(),
            const SizedBox(height: 20),
            _buildSectionHeader('Recent Transactions',
                onSeeAll: () => Navigator.pushNamed(context, AppRoutes.transactions)),
            _buildRecentTransactions(income, expense),
          ],
        ),
      ),
    );
  }

  Widget _buildGreeting(String username) {
    final hour = DateTime.now().hour;
    final greeting = hour < 12 ? 'Good morning' : hour < 17 ? 'Good afternoon' : 'Good evening';
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$greeting,', style: TextStyle(fontSize: 14, color: cs.onSurface.withOpacity(0.6))),
          Text(username, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: cs.onSurface)),
          Text(DateFormat('MMMM yyyy').format(DateTime.now()),
              style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(0.6))),
        ],
      ),
    );
  }

  Widget _buildScoreCard(AnalysisResultModel result) {
    final color = AppTheme.scoreColor(result.category);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [color.withOpacity(0.85), color],
            begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: color.withOpacity(0.35), blurRadius: 16, offset: const Offset(0, 6))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Financial Score', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(20)),
                child: Text(result.category, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${result.score.toInt()}', style: const TextStyle(color: Colors.white, fontSize: 56, fontWeight: FontWeight.w800, height: 1)),
              const Padding(padding: EdgeInsets.only(bottom: 8, left: 4),
                  child: Text('/100', style: TextStyle(color: Colors.white60, fontSize: 18, fontWeight: FontWeight.w500))),
            ],
          ),
          const SizedBox(height: 6),
          Text(result.persona, style: const TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(value: result.score / 100,
                backgroundColor: Colors.white24,
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.white), minHeight: 6),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _trendIcon(result.spendingTrend),
              const SizedBox(width: 6),
              Text(_trendLabel(result.spendingTrend), style: const TextStyle(color: Colors.white70, fontSize: 12)),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.pushNamed(context, AppRoutes.insights),
                style: TextButton.styleFrom(foregroundColor: Colors.white, padding: EdgeInsets.zero,
                    minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                child: const Text('View Insights →', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildScoreCardSkeleton() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16), height: 190,
      decoration: BoxDecoration(color: Theme.of(context).dividerColor, borderRadius: BorderRadius.circular(16)),
      child: const Center(child: CircularProgressIndicator(color: AppTheme.primary)),
    );
  }

  Widget _buildScoreCardEmpty() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [AppTheme.primary.withOpacity(0.7), AppTheme.primary],
            begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: AppTheme.primary.withOpacity(0.3), blurRadius: 16, offset: const Offset(0, 6))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Financial Score', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(20)),
                child: const Text('No Data', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('0', style: TextStyle(color: Colors.white54, fontSize: 56, fontWeight: FontWeight.w800, height: 1)),
              Padding(padding: EdgeInsets.only(bottom: 8, left: 4),
                  child: Text('/100', style: TextStyle(color: Colors.white38, fontSize: 18))),
            ],
          ),
          const SizedBox(height: 6),
          const Text('No transactions recorded yet', style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 16),
          const ClipRRect(
            borderRadius: BorderRadius.all(Radius.circular(4)),
            child: LinearProgressIndicator(value: 0, backgroundColor: Colors.white24,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white), minHeight: 6),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.trending_flat, size: 16, color: Colors.white70),
              const SizedBox(width: 6),
              const Text('Spending stable', style: TextStyle(color: Colors.white70, fontSize: 12)),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.pushNamed(context, AppRoutes.insights),
                style: TextButton.styleFrom(foregroundColor: Colors.white, padding: EdgeInsets.zero,
                    minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                child: const Text('View Insights →', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOnboardingChecklist() {
    final cs = Theme.of(context).colorScheme;
    final divider = Theme.of(context).dividerColor;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface, borderRadius: BorderRadius.circular(14),
        border: Border.all(color: divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: AppTheme.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.rocket_launch_outlined, size: 20, color: AppTheme.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Get Started', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: cs.onSurface)),
                    Text('Complete these steps to set up your tracker',
                        style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.6))),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Divider(height: 1, color: divider),
          const SizedBox(height: 12),
          _onboardingStep(step: '1', icon: Icons.account_balance_wallet_outlined,
              title: 'Add your income', subtitle: 'Log your HELB, stipend, or salary for this month',
              onTap: () => Navigator.pushNamed(context, AppRoutes.addIncome), isDone: false),
          const SizedBox(height: 10),
          _onboardingStep(step: '2', icon: Icons.receipt_long_outlined,
              title: 'Log an expense', subtitle: 'Record what you spend — food, transport, rent, etc.',
              onTap: () => Navigator.pushNamed(context, AppRoutes.addExpense), isDone: false),
          const SizedBox(height: 10),
          _onboardingStep(step: '3', icon: Icons.pie_chart_outline,
              title: 'Set a budget', subtitle: 'Define spending limits per category for the month',
              onTap: () => Navigator.pushNamed(context, AppRoutes.addBudget), isDone: false),
          const SizedBox(height: 10),
          _onboardingStep(step: '4', icon: Icons.flag_outlined,
              title: 'Create a savings goal', subtitle: 'Set a target — laptop, rent deposit, emergency fund',
              onTap: () => Navigator.pushNamed(context, AppRoutes.addGoal), isDone: false),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppTheme.primary.withOpacity(0.06), borderRadius: BorderRadius.circular(10)),
            child: Row(
              children: [
                const Icon(Icons.lightbulb_outline, size: 16, color: AppTheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.6)),
                      children: const [
                        TextSpan(text: 'Tip: ', style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.primary)),
                        TextSpan(text: 'Your financial score updates automatically after you add income and expenses.'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _onboardingStep({
    required String step, required IconData icon, required String title,
    required String subtitle, required VoidCallback onTap, required bool isDone,
  }) {
    final cs = Theme.of(context).colorScheme;
    final bg = Theme.of(context).scaffoldBackgroundColor;
    final divider = Theme.of(context).dividerColor;
    return InkWell(
      onTap: onTap, borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isDone ? AppTheme.primary.withOpacity(0.05) : bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isDone ? AppTheme.primary.withOpacity(0.2) : divider),
        ),
        child: Row(
          children: [
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                  color: isDone ? AppTheme.primary : AppTheme.primary.withOpacity(0.12), shape: BoxShape.circle),
              child: Center(
                child: isDone
                    ? const Icon(Icons.check, size: 14, color: Colors.white)
                    : Text(step, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold,
                        color: isDone ? Colors.white : AppTheme.primary)),
              ),
            ),
            const SizedBox(width: 12),
            Icon(icon, size: 18, color: isDone ? AppTheme.primary : cs.onSurface.withOpacity(0.5)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13,
                      color: isDone ? AppTheme.primary : cs.onSurface,
                      decoration: isDone ? TextDecoration.lineThrough : null)),
                  Text(subtitle, style: TextStyle(fontSize: 11, color: cs.onSurface.withOpacity(0.6))),
                ],
              ),
            ),
            Icon(isDone ? Icons.check_circle : Icons.chevron_right,
                size: 18, color: isDone ? AppTheme.primary : cs.onSurface.withOpacity(0.5)),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryRow({required double income, required double expenses, required double balance}) {
    final fmt = NumberFormat('#,##0', 'en_US');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(child: _summaryCard(label: 'Income',
              amount: '${AppConstants.currency} ${fmt.format(income)}',
              icon: Icons.arrow_downward, color: AppTheme.success, isEmpty: income == 0)),
          const SizedBox(width: 10),
          Expanded(child: _summaryCard(label: 'Expenses',
              amount: '${AppConstants.currency} ${fmt.format(expenses)}',
              icon: Icons.arrow_upward, color: AppTheme.error, isEmpty: expenses == 0)),
          const SizedBox(width: 10),
          Expanded(child: _summaryCard(label: 'Balance',
              amount: '${AppConstants.currency} ${fmt.format(balance)}',
              icon: Icons.account_balance_wallet_outlined,
              color: balance >= 0 ? AppTheme.info : AppTheme.warning,
              isEmpty: income == 0 && expenses == 0)),
        ],
      ),
    );
  }

  Widget _summaryCard({
    required String label, required String amount,
    required IconData icon, required Color color, bool isEmpty = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surface, borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: isEmpty ? cs.onSurface.withOpacity(0.3) : color),
          const SizedBox(height: 8),
          Text(label, style: TextStyle(fontSize: 11, color: cs.onSurface.withOpacity(0.6))),
          const SizedBox(height: 2),
          isEmpty
              ? Text('KES 0', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.onSurface.withOpacity(0.3)))
              : Text(amount, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  Widget _buildGoalBanner(String goalHealth, bool noGoalSet) {
    final Color color;
    final String message;
    if (noGoalSet) {
      color = AppTheme.primary; message = 'No savings goal set. Tap to set one →';
    } else {
      final isGood = goalHealth.toLowerCase().contains('on track') || goalHealth.toLowerCase().contains('achieved');
      color = isGood ? AppTheme.success : AppTheme.warning;
      message = goalHealth;
    }
    return GestureDetector(
      onTap: () => Navigator.pushNamed(context, AppRoutes.goals),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Icon(Icons.flag_outlined, size: 18, color: color),
            const SizedBox(width: 10),
            Expanded(child: Text(message, style: TextStyle(fontSize: 13, color: color))),
            Icon(Icons.chevron_right, size: 18, color: color),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, {VoidCallback? onSeeAll}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurface)),
          if (onSeeAll != null) TextButton(onPressed: onSeeAll, child: const Text('See All')),
        ],
      ),
    );
  }

  Widget _buildRecentTransactions(IncomeProvider income, ExpenseProvider expense) {
    final cs = Theme.of(context).colorScheme;
    final divider = Theme.of(context).dividerColor;
    final transactions = [
      ...income.records.map((r) => _TransactionItem(
          label: r.description.isNotEmpty ? r.description : r.incomeType,
          amount: r.amount, date: r.dateAdded, isIncome: true)),
      ...expense.records.map((r) => _TransactionItem(
          label: r.description.isNotEmpty ? r.description : r.category,
          amount: r.amount, date: r.dateAdded, isIncome: false, category: r.category)),
    ]..sort((a, b) => b.date.compareTo(a.date));
    final recent = transactions.take(5).toList();

    if (income.isLoading || expense.isLoading) {
      return const Padding(padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator(color: AppTheme.primary)));
    }

    if (recent.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(14),
              border: Border.all(color: divider)),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: AppTheme.primary.withOpacity(0.08), shape: BoxShape.circle),
                child: const Icon(Icons.receipt_long_outlined, size: 32, color: AppTheme.primary),
              ),
              const SizedBox(height: 14),
              Text('No transactions yet', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: cs.onSurface)),
              const SizedBox(height: 6),
              Text('Start logging your income and expenses\nto track your financial health.',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(0.6))),
              const SizedBox(height: 16),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                OutlinedButton.icon(onPressed: () => Navigator.pushNamed(context, AppRoutes.addIncome),
                    icon: const Icon(Icons.add, size: 16), label: const Text('Add Income'),
                    style: OutlinedButton.styleFrom(foregroundColor: AppTheme.success,
                        side: const BorderSide(color: AppTheme.success))),
                const SizedBox(width: 12),
                OutlinedButton.icon(onPressed: () => Navigator.pushNamed(context, AppRoutes.addExpense),
                    icon: const Icon(Icons.add, size: 16), label: const Text('Add Expense'),
                    style: OutlinedButton.styleFrom(foregroundColor: AppTheme.error,
                        side: const BorderSide(color: AppTheme.error))),
              ]),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: recent.length,
      itemBuilder: (context, index) {
        final t = recent[index];
        final fmt = NumberFormat('#,##0.00', 'en_US');
        final dateFmt = DateFormat('dd MMM').format(DateTime.parse(t.date).toLocal());
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: cs.surface, borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
          ),
          child: Row(
            children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                    color: (t.isIncome ? AppTheme.success : AppTheme.error).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10)),
                child: Icon(t.isIncome ? Icons.arrow_downward : Icons.arrow_upward,
                    size: 18, color: t.isIncome ? AppTheme.success : AppTheme.error),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.label, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: cs.onSurface),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(t.isIncome ? dateFmt : '${t.category} · $dateFmt',
                        style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.6))),
                  ],
                ),
              ),
              Text('${t.isIncome ? '+' : '-'} ${AppConstants.currency} ${fmt.format(t.amount)}',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14,
                      color: t.isIncome ? AppTheme.success : AppTheme.error)),
            ],
          ),
        );
      },
    );
  }

  Widget _trendIcon(String trend) {
    IconData icon; Color color;
    switch (trend) {
      case 'improving':      icon = Icons.trending_up;   color = Colors.white;   break;
      case 'worsening_fast': icon = Icons.trending_down; color = Colors.white;   break;
      case 'worsening_slow': icon = Icons.trending_down; color = Colors.white70; break;
      default:               icon = Icons.trending_flat; color = Colors.white70;
    }
    return Icon(icon, size: 16, color: color);
  }

  String _trendLabel(String trend) {
    switch (trend) {
      case 'improving':      return 'Spending improving';
      case 'worsening_fast': return 'Spending worsening fast';
      case 'worsening_slow': return 'Spending worsening slowly';
      default:               return 'Spending stable';
    }
  }
}

class _TransactionItem {
  final String label; final double amount; final String date;
  final bool isIncome; final String category;
  _TransactionItem({required this.label, required this.amount,
      required this.date, required this.isIncome, this.category = ''});
}