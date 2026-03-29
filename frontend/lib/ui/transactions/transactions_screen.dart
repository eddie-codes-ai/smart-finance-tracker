// lib/ui/transactions/transactions_screen.dart
// Shows combined income and expense history for the current month.
// Supports month navigation, filtering by type, swipe-to-delete, and edit.
//
// CHANGES from original:
//   1. All tab now also supports swipe-to-delete
//   2. Edit icon added to every transaction tile
//   3. Tapping edit navigates to EditTransactionScreen

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../core/constants.dart';
import '../../providers/income_provider.dart';
import '../../providers/expense_provider.dart';
import '../../models/income_model.dart';
import '../../models/expense_model.dart';
import 'edit_transaction_screen.dart';

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late DateTime _selectedMonth;
  bool _initialLoadDone = false;

  @override
  void initState() {
    super.initState();
    _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
    _tabController = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (_initialLoadDone) return;
    _initialLoadDone = true;
    await _fetchForMonth(_selectedMonth);
  }

  Future<void> _fetchForMonth(DateTime month) async {
    await Future.wait([
      context.read<IncomeProvider>().fetchIncome(
            month: month.month,
            year: month.year,
          ),
      context.read<ExpenseProvider>().fetchExpenses(
            month: month.month,
            year: month.year,
          ),
    ]);
  }

  void _previousMonth() {
    setState(() {
      _selectedMonth =
          DateTime(_selectedMonth.year, _selectedMonth.month - 1);
    });
    _fetchForMonth(_selectedMonth);
  }

  void _nextMonth() {
    final now = DateTime.now();
    if (_selectedMonth.year == now.year &&
        _selectedMonth.month == now.month) return;
    setState(() {
      _selectedMonth =
          DateTime(_selectedMonth.year, _selectedMonth.month + 1);
    });
    _fetchForMonth(_selectedMonth);
  }

  // ── Navigate to edit screen ───────────────────────────────────────────────

  Future<void> _editExpense(ExpenseModel r) async {
    final edited = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EditTransactionScreen.expense(expense: r),
      ),
    );
    // Refresh list if something was changed
    if (edited == true) _fetchForMonth(_selectedMonth);
  }

  Future<void> _editIncome(IncomeModel r) async {
    final edited = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EditTransactionScreen.income(income: r),
      ),
    );
    if (edited == true) _fetchForMonth(_selectedMonth);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildMonthNavigator(),
        Container(
          color: AppTheme.surface,
          child: TabBar(
            controller: _tabController,
            labelColor: AppTheme.primary,
            unselectedLabelColor: AppTheme.textSecondary,
            indicatorColor: AppTheme.primary,
            tabs: const [
              Tab(text: 'All'),
              Tab(text: 'Income'),
              Tab(text: 'Expenses'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildAllTab(),
              _buildIncomeTab(),
              _buildExpensesTab(),
            ],
          ),
        ),
      ],
    );
  }

  // ─── Month Navigator ──────────────────────────────────────────────────────
  Widget _buildMonthNavigator() {
    final now = DateTime.now();
    final isCurrentMonth = _selectedMonth.year == now.year &&
        _selectedMonth.month == now.month;

    return Container(
      color: AppTheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: _previousMonth,
            color: AppTheme.primary,
          ),
          Text(
            DateFormat('MMMM yyyy').format(_selectedMonth),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: isCurrentMonth ? null : _nextMonth,
            color: isCurrentMonth ? AppTheme.divider : AppTheme.primary,
          ),
        ],
      ),
    );
  }

  // ─── All Tab — NOW includes swipe-to-delete ───────────────────────────────
  Widget _buildAllTab() {
    final income  = context.watch<IncomeProvider>();
    final expense = context.watch<ExpenseProvider>();

    if (income.isLoading || expense.isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: AppTheme.primary));
    }

    final List<_TxItem> all = [
      ...income.records.map((r)  => _TxItem.fromIncome(r)),
      ...expense.records.map((r) => _TxItem.fromExpense(r)),
    ]..sort((a, b) => b.date.compareTo(a.date));

    if (all.isEmpty) return _buildEmptyState();

    return RefreshIndicator(
      onRefresh: () => _fetchForMonth(_selectedMonth),
      color: AppTheme.primary,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: all.length,
        itemBuilder: (context, index) {
          final item = all[index];
          // Find the actual model so we can pass it to edit/delete
          if (item.isIncome) {
            final model = income.records
                .firstWhere((r) => r.id == item.id);
            return _buildDismissibleIncome(model, fromAllTab: true);
          } else {
            final model = expense.records
                .firstWhere((r) => r.id == item.id);
            return _buildDismissibleExpense(model, fromAllTab: true);
          }
        },
      ),
    );
  }

  // ─── Income Tab ───────────────────────────────────────────────────────────
  Widget _buildIncomeTab() {
    final provider = context.watch<IncomeProvider>();

    if (provider.isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: AppTheme.primary));
    }

    if (provider.records.isEmpty) return _buildEmptyState(type: 'income');

    return Column(
      children: [
        _buildTotalBanner(
          label: 'Total Income',
          amount: provider.total,
          color: AppTheme.success,
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => _fetchForMonth(_selectedMonth),
            color: AppTheme.primary,
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: provider.records.length,
              itemBuilder: (context, index) =>
                  _buildDismissibleIncome(provider.records[index]),
            ),
          ),
        ),
      ],
    );
  }

  // ─── Expenses Tab ─────────────────────────────────────────────────────────
  Widget _buildExpensesTab() {
    final provider = context.watch<ExpenseProvider>();

    if (provider.isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: AppTheme.primary));
    }

    if (provider.records.isEmpty) return _buildEmptyState(type: 'expense');

    return Column(
      children: [
        _buildTotalBanner(
          label: 'Total Expenses',
          amount: provider.total,
          color: AppTheme.error,
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => _fetchForMonth(_selectedMonth),
            color: AppTheme.primary,
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: provider.records.length,
              itemBuilder: (context, index) =>
                  _buildDismissibleExpense(provider.records[index]),
            ),
          ),
        ),
      ],
    );
  }

  // ─── Dismissible Income Tile ──────────────────────────────────────────────
  Widget _buildDismissibleIncome(IncomeModel r,
      {bool fromAllTab = false}) {
    return Dismissible(
      key: Key('income_${r.id}_${fromAllTab ? 'all' : 'tab'}'),
      direction: DismissDirection.endToStart,
      background: _deleteBackground(),
      confirmDismiss: (_) => _confirmDelete(),
      onDismissed: (_) async {
        final success =
            await context.read<IncomeProvider>().deleteIncome(r.id);
        if (!success && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to delete income record.'),
              backgroundColor: AppTheme.error,
            ),
          );
        }
      },
      child: _buildTxTile(
        _TxItem.fromIncome(r),
        onEdit: () => _editIncome(r),
      ),
    );
  }

  // ─── Dismissible Expense Tile ─────────────────────────────────────────────
  Widget _buildDismissibleExpense(ExpenseModel r,
      {bool fromAllTab = false}) {
    return Dismissible(
      key: Key('expense_${r.id}_${fromAllTab ? 'all' : 'tab'}'),
      direction: DismissDirection.endToStart,
      background: _deleteBackground(),
      confirmDismiss: (_) => _confirmDelete(),
      onDismissed: (_) async {
        final success =
            await context.read<ExpenseProvider>().deleteExpense(r.id);
        if (!success && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to delete expense record.'),
              backgroundColor: AppTheme.error,
            ),
          );
        }
      },
      child: _buildTxTile(
        _TxItem.fromExpense(r),
        onEdit: () => _editExpense(r),
      ),
    );
  }

  // ─── Transaction Tile — now has edit icon ─────────────────────────────────
  Widget _buildTxTile(_TxItem t, {VoidCallback? onEdit}) {
    final fmt     = NumberFormat('#,##0.00', 'en_US');
    final dateFmt = DateFormat('dd MMM, hh:mm a')
        .format(DateTime.parse(t.date));

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
          // Category icon
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: (t.isIncome ? AppTheme.success : AppTheme.error)
                  .withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              t.isIncome
                  ? Icons.arrow_downward
                  : _categoryIcon(t.category),
              size: 20,
              color: t.isIncome ? AppTheme.success : AppTheme.error,
            ),
          ),
          const SizedBox(width: 12),

          // Label + subtitle
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
                const SizedBox(height: 2),
                Text(
                  t.isIncome
                      ? '${t.subLabel} · $dateFmt'
                      : '${t.category} · $dateFmt',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),

          // Amount
          Text(
            '${t.isIncome ? '+' : '-'} ${AppConstants.currency} ${fmt.format(t.amount)}',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: t.isIncome ? AppTheme.success : AppTheme.error,
            ),
          ),

          // ── Edit icon ────────────────────────────────────────────────────
          if (onEdit != null) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onEdit,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.edit_outlined,
                  size: 16,
                  color: AppTheme.primary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────
  Widget _buildTotalBanner({
    required String label,
    required double amount,
    required Color color,
  }) {
    final fmt = NumberFormat('#,##0.00', 'en_US');
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: color)),
          Text(
            '${AppConstants.currency} ${fmt.format(amount)}',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState({String? type}) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.receipt_long_outlined,
              size: 52, color: AppTheme.textSecondary),
          const SizedBox(height: 12),
          Text(
            type == 'income'
                ? 'No income recorded this month.'
                : type == 'expense'
                    ? 'No expenses recorded this month.'
                    : 'No transactions this month.',
            style: const TextStyle(color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _deleteBackground() {
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 20),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.error,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(Icons.delete_outline,
          color: Colors.white, size: 26),
    );
  }

  Future<bool?> _confirmDelete() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Record'),
        content: const Text('This record will be permanently deleted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  IconData _categoryIcon(String category) {
    switch (category) {
      case 'Food':         return Icons.restaurant_outlined;
      case 'Transport':   return Icons.directions_bus_outlined;
      case 'Entertainment': return Icons.movie_outlined;
      case 'Shopping':    return Icons.shopping_bag_outlined;
      case 'Health':      return Icons.local_hospital_outlined;
      case 'Education':   return Icons.school_outlined;
      case 'Utilities':   return Icons.bolt_outlined;
      case 'Rent':        return Icons.home_outlined;
      default:            return Icons.category_outlined;
    }
  }
}

// Internal model combining income and expense into one list.
class _TxItem {
  final int    id;
  final String label;
  final String subLabel;
  final String category;
  final double amount;
  final String date;
  final bool   isIncome;

  _TxItem({
    required this.id,
    required this.label,
    required this.subLabel,
    required this.category,
    required this.amount,
    required this.date,
    required this.isIncome,
  });

  factory _TxItem.fromIncome(IncomeModel r) => _TxItem(
        id:       r.id,
        label:    r.description.isNotEmpty ? r.description : r.incomeType,
        subLabel: r.incomeType,
        category: '',
        amount:   r.amount,
        date:     r.dateAdded,
        isIncome: true,
      );

  factory _TxItem.fromExpense(ExpenseModel r) => _TxItem(
        id:       r.id,
        label:    r.description.isNotEmpty ? r.description : r.category,
        subLabel: r.expenseType,
        category: r.category,
        amount:   r.amount,
        date:     r.dateAdded,
        isIncome: false,
      );
}