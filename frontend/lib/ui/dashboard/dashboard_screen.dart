// lib/ui/dashboard/dashboard_screen.dart
// Main dashboard shown after login.
// Displays: financial score card, income/expenses/savings summary,
// recent transactions list, and a goal health banner.
// Calls analyze() on first load to populate the score and advice.
//
// FIX: Wrapped build() return in Material(color: AppTheme.background)
// to prevent yellow-underline / dark-background rendering issue that
// occurs with useMaterial3:true when scaffoldBackgroundColor is not
// inherited properly through IndexedStack on some Flutter/Impeller builds.

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
      context.read<AnalysisProvider>().analyze(
            month: now.month,
            year: now.year,
          ),
      context.read<IncomeProvider>().fetchIncome(
            month: now.month,
            year: now.year,
          ),
      context.read<ExpenseProvider>().fetchExpenses(
            month: now.month,
            year: now.year,
          ),
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

    final goalHealth  = analysis.hasResult ? analysis.result!.goalHealth : '';
    final noGoalSet   = goalHealth == 'No savings goal set.';
    final showGoalBanner = analysis.hasResult;

    // Material wrapper ensures correct background colour and text styling
    // even when rendered inside IndexedStack with useMaterial3:true theme.
    return Material(
      color: AppTheme.background,
      child: RefreshIndicator(
        onRefresh: _refresh,
        color: AppTheme.primary,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Greeting ─────────────────────────────────────────────────
              _buildGreeting(auth.user?.username ?? 'Student'),

              // ── Score Card ───────────────────────────────────────────────
              if (analysis.isLoading)
                _buildScoreCardSkeleton()
              else if (analysis.hasResult)
                _buildScoreCard(analysis.result!)
              else
                _buildScoreCardEmpty(analysis.errorMessage),

              const SizedBox(height: 16),

              // ── Summary Cards ─────────────────────────────────────────────
              _buildSummaryRow(
                income:   income.total,
                expenses: expense.total,
                savings:  income.total - expense.total,
              ),

              const SizedBox(height: 20),

              // ── Goal Health Banner ────────────────────────────────────────
              if (showGoalBanner)
                _buildGoalBanner(goalHealth, noGoalSet),

              const SizedBox(height: 20),

              // ── Recent Transactions ───────────────────────────────────────
              _buildSectionHeader('Recent Transactions', onSeeAll: () {}),
              _buildRecentTransactions(income, expense),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Greeting ─────────────────────────────────────────────────────────────
  Widget _buildGreeting(String username) {
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 17
            ? 'Good afternoon'
            : 'Good evening';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$greeting,',
            style: const TextStyle(
              fontSize: 14,
              color: AppTheme.textSecondary,
            ),
          ),
          Text(
            username,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          Text(
            DateFormat('MMMM yyyy').format(DateTime.now()),
            style: const TextStyle(
              fontSize: 13,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Score Card ───────────────────────────────────────────────────────────
  Widget _buildScoreCard(AnalysisResultModel result) {
    final color = AppTheme.scoreColor(result.category);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withOpacity(0.85), color],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Financial Score',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  result.category,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${result.score.toInt()}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 56,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(bottom: 8, left: 4),
                child: Text(
                  '/100',
                  style: TextStyle(
                    color: Colors.white60,
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            result.persona,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: result.score / 100,
              backgroundColor: Colors.white24,
              valueColor:
                  const AlwaysStoppedAnimation<Color>(Colors.white),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _trendIcon(result.spendingTrend),
              const SizedBox(width: 6),
              Text(
                _trendLabel(result.spendingTrend),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const Spacer(),
              TextButton(
                onPressed: () =>
                    Navigator.pushNamed(context, AppRoutes.insights),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'View Insights →',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildScoreCardSkeleton() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      height: 190,
      decoration: BoxDecoration(
        color: AppTheme.divider,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Center(
        child: CircularProgressIndicator(color: AppTheme.primary),
      ),
    );
  }

  Widget _buildScoreCardEmpty(String? error) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        children: [
          const Icon(Icons.analytics_outlined,
              size: 40, color: AppTheme.textSecondary),
          const SizedBox(height: 12),
          Text(
            error ??
                'Add income and expenses to see your financial score.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }

  // ─── Summary Row ──────────────────────────────────────────────────────────
  Widget _buildSummaryRow({
    required double income,
    required double expenses,
    required double savings,
  }) {
    final fmt = NumberFormat('#,##0', 'en_US');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: _summaryCard(
              label:  'Income',
              amount: '${AppConstants.currency} ${fmt.format(income)}',
              icon:   Icons.arrow_downward,
              color:  AppTheme.success,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _summaryCard(
              label:  'Expenses',
              amount: '${AppConstants.currency} ${fmt.format(expenses)}',
              icon:   Icons.arrow_upward,
              color:  AppTheme.error,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _summaryCard(
              label:  'Savings',
              amount: '${AppConstants.currency} ${fmt.format(savings)}',
              icon:   Icons.savings_outlined,
              color:  savings >= 0 ? AppTheme.info : AppTheme.warning,
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryCard({
    required String  label,
    required String  amount,
    required IconData icon,
    required Color   color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            amount,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // ─── Goal Banner ──────────────────────────────────────────────────────────
  Widget _buildGoalBanner(String goalHealth, bool noGoalSet) {
    final Color color;
    final IconData icon;
    final String message;

    if (noGoalSet) {
      color   = AppTheme.primary;
      icon    = Icons.flag_outlined;
      message = 'No savings goal set. Tap to set one →';
    } else {
      final isGood = goalHealth.toLowerCase().contains('on track') ||
          goalHealth.toLowerCase().contains('achieved');
      color   = isGood ? AppTheme.success : AppTheme.warning;
      icon    = Icons.flag_outlined;
      message = goalHealth;
    }

    return GestureDetector(
      onTap: () => Navigator.pushNamed(context, AppRoutes.goals),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(fontSize: 13, color: color),
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: color),
          ],
        ),
      ),
    );
  }

  // ─── Section Header ───────────────────────────────────────────────────────
  Widget _buildSectionHeader(String title, {VoidCallback? onSeeAll}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          if (onSeeAll != null)
            TextButton(
              onPressed: onSeeAll,
              child: const Text('See All'),
            ),
        ],
      ),
    );
  }

  // ─── Recent Transactions ──────────────────────────────────────────────────
  Widget _buildRecentTransactions(
    IncomeProvider income,
    ExpenseProvider expense,
  ) {
    final transactions = [
      ...income.records.map((r) => _TransactionItem(
            label:    r.description.isNotEmpty ? r.description : r.incomeType,
            amount:   r.amount,
            date:     r.dateAdded,
            isIncome: true,
          )),
      ...expense.records.map((r) => _TransactionItem(
            label:    r.description.isNotEmpty ? r.description : r.category,
            amount:   r.amount,
            date:     r.dateAdded,
            isIncome: false,
            category: r.category,
          )),
    ]..sort((a, b) => b.date.compareTo(a.date));

    final recent = transactions.take(5).toList();

    if (income.isLoading || expense.isLoading) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(
            child: CircularProgressIndicator(color: AppTheme.primary)),
      );
    }

    if (recent.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.receipt_long_outlined,
                  size: 48, color: AppTheme.textSecondary),
              SizedBox(height: 12),
              Text(
                'No transactions yet.\nTap + to add your first record.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textSecondary),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: recent.length,
      itemBuilder: (context, index) {
        final t       = recent[index];
        final fmt     = NumberFormat('#,##0.00', 'en_US');
        final dateFmt =
            DateFormat('dd MMM').format(DateTime.parse(t.date));

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color:
                      (t.isIncome ? AppTheme.success : AppTheme.error)
                          .withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  t.isIncome
                      ? Icons.arrow_downward
                      : Icons.arrow_upward,
                  size: 18,
                  color:
                      t.isIncome ? AppTheme.success : AppTheme.error,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.label,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: AppTheme.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      t.isIncome
                          ? dateFmt
                          : '${t.category} · $dateFmt',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${t.isIncome ? '+' : '-'} ${AppConstants.currency} ${fmt.format(t.amount)}',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color:
                      t.isIncome ? AppTheme.success : AppTheme.error,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────
  Widget _trendIcon(String trend) {
    IconData icon;
    Color color;
    switch (trend) {
      case 'improving':
        icon  = Icons.trending_up;
        color = Colors.white;
        break;
      case 'worsening_fast':
        icon  = Icons.trending_down;
        color = Colors.white;
        break;
      case 'worsening_slow':
        icon  = Icons.trending_down;
        color = Colors.white70;
        break;
      default:
        icon  = Icons.trending_flat;
        color = Colors.white70;
    }
    return Icon(icon, size: 16, color: color);
  }

  String _trendLabel(String trend) {
    switch (trend) {
      case 'improving':       return 'Spending improving';
      case 'worsening_fast':  return 'Spending worsening fast';
      case 'worsening_slow':  return 'Spending worsening slowly';
      default:                return 'Spending stable';
    }
  }
}

// ─── Internal model ───────────────────────────────────────────────────────────
class _TransactionItem {
  final String  label;
  final double  amount;
  final String  date;
  final bool    isIncome;
  final String  category;

  _TransactionItem({
    required this.label,
    required this.amount,
    required this.date,
    required this.isIncome,
    this.category = '',
  });
}