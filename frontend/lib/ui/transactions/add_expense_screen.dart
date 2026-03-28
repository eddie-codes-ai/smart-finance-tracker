// lib/ui/transactions/add_expense_screen.dart
// Form screen to log a new expense record.
// Fields: amount, category, expense_type, recurrence_interval, description.
// Shows recurrence interval picker only when expense_type is 'recurring'.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../core/constants.dart';
import '../../providers/expense_provider.dart';
import '../../providers/budget_provider.dart';
import '../../providers/analysis_provider.dart';

class AddExpenseScreen extends StatefulWidget {
  const AddExpenseScreen({super.key});

  @override
  State<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends State<AddExpenseScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();

  String _selectedCategory = 'Food';
  String _selectedExpenseType = 'daily';
  String? _selectedRecurrence;

  // Category icons matching TransactionsScreen
  static const Map<String, IconData> _categoryIcons = {
    'Food': Icons.restaurant_outlined,
    'Transport': Icons.directions_bus_outlined,
    'Entertainment': Icons.movie_outlined,
    'Shopping': Icons.shopping_bag_outlined,
    'Health': Icons.local_hospital_outlined,
    'Education': Icons.school_outlined,
    'Utilities': Icons.bolt_outlined,
    'Rent': Icons.home_outlined,
    'Other': Icons.category_outlined,
  };

  static const List<String> _recurrenceOptions = [
    'daily',
    'weekly',
    'biweekly',
    'monthly',
  ];

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    // Recurrence interval only sent if expense_type is recurring.
    final recurrence =
        _selectedExpenseType == 'recurring' ? _selectedRecurrence : null;

    // Look up the budget limit for the selected category.
    // Returns null if the student has not set a budget for this category —
    // in that case no notification will fire (nothing to compare against).
    final double? budgetLimit =
        context.read<BudgetProvider>().limitFor(_selectedCategory);

    final provider = context.read<ExpenseProvider>();
    final success = await provider.addExpense(
      amount: double.parse(_amountController.text.trim()),
      category: _selectedCategory,
      description: _descriptionController.text.trim(),
      expenseType: _selectedExpenseType,
      recurrenceInterval: recurrence,
      budgetLimit: budgetLimit, // ← triggers notification check in provider
    );

    if (!mounted) return;

    if (success) {
      context.read<AnalysisProvider>().clear();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Expense added successfully.'),
          backgroundColor: AppTheme.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(provider.errorMessage ?? 'Failed to add expense.'),
          backgroundColor: AppTheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = context.watch<ExpenseProvider>().isLoading;

    return Scaffold(
      appBar: AppBar(title: const Text('Add Expense')),
      backgroundColor: AppTheme.background,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Amount ──────────────────────────────────────────────────
              const Text('Amount (KES)',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary,
                      fontSize: 13)),
              const SizedBox(height: 8),
              TextFormField(
                controller: _amountController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                      RegExp(r'^\d+\.?\d{0,2}')),
                ],
                decoration: const InputDecoration(
                  hintText: '0.00',
                  prefixText: 'KES  ',
                  prefixIcon: Icon(Icons.attach_money),
                ),
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w700),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter an amount.';
                  }
                  if (double.tryParse(value) == null ||
                      double.parse(value) <= 0) {
                    return 'Please enter a valid amount greater than 0.';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 24),

              // ── Category ─────────────────────────────────────────────────
              const Text('Category',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary,
                      fontSize: 13)),
              const SizedBox(height: 8),
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 2.2,
                children: AppConstants.expenseCategories.map((cat) {
                  final isSelected = _selectedCategory == cat;
                  return GestureDetector(
                    onTap: () =>
                        setState(() => _selectedCategory = cat),
                    child: Container(
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppTheme.primary
                            : AppTheme.surface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected
                              ? AppTheme.primary
                              : AppTheme.divider,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _categoryIcons[cat] ??
                                Icons.category_outlined,
                            size: 14,
                            color: isSelected
                                ? Colors.white
                                : AppTheme.textSecondary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            cat,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isSelected
                                  ? Colors.white
                                  : AppTheme.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),

              const SizedBox(height: 24),

              // ── Expense Type ─────────────────────────────────────────────
              const Text('Expense Type',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary,
                      fontSize: 13)),
              const SizedBox(height: 4),
              const Text(
                'One-time expenses are excluded from daily budget calculations.',
                style: TextStyle(
                    fontSize: 11, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: AppConstants.expenseTypes.map((type) {
                  final isSelected = _selectedExpenseType == type;
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedExpenseType = type;
                        if (type != 'recurring') {
                          _selectedRecurrence = null;
                        }
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppTheme.primary
                            : AppTheme.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected
                              ? AppTheme.primary
                              : AppTheme.divider,
                        ),
                      ),
                      child: Text(
                        _expenseTypeLabel(type),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isSelected
                              ? Colors.white
                              : AppTheme.textPrimary,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),

              // ── Recurrence Interval (only if recurring) ──────────────────
              if (_selectedExpenseType == 'recurring') ...[
                const SizedBox(height: 20),
                const Text('Recurrence Interval',
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textSecondary,
                        fontSize: 13)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _selectedRecurrence,
                  hint: const Text('Select interval'),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.repeat),
                  ),
                  items: _recurrenceOptions
                      .map((r) => DropdownMenuItem(
                            value: r,
                            child: Text(_recurrenceLabel(r)),
                          ))
                      .toList(),
                  onChanged: (value) =>
                      setState(() => _selectedRecurrence = value),
                  validator: (value) {
                    if (_selectedExpenseType == 'recurring' &&
                        (value == null || value.isEmpty)) {
                      return 'Please select a recurrence interval.';
                    }
                    return null;
                  },
                ),
              ],

              const SizedBox(height: 24),

              // ── Description ──────────────────────────────────────────────
              const Text('Description (optional)',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary,
                      fontSize: 13)),
              const SizedBox(height: 8),
              TextFormField(
                controller: _descriptionController,
                textInputAction: TextInputAction.done,
                maxLength: 100,
                decoration: const InputDecoration(
                  hintText: 'e.g. Lunch at Java, Bus fare to town...',
                  prefixIcon: Icon(Icons.notes_outlined),
                ),
              ),

              const SizedBox(height: 32),

              // ── Submit ───────────────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: isLoading ? null : _submit,
                  icon: isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.check),
                  label: Text(
                      isLoading ? 'Saving...' : 'Save Expense Record'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _expenseTypeLabel(String type) {
    switch (type) {
      case 'daily':
        return 'Daily';
      case 'monthly':
        return 'Monthly';
      case 'one-time':
        return 'One-Time';
      case 'recurring':
        return 'Recurring';
      default:
        return type;
    }
  }

  String _recurrenceLabel(String r) {
    switch (r) {
      case 'daily':
        return 'Every Day';
      case 'weekly':
        return 'Every Week';
      case 'biweekly':
        return 'Every 2 Weeks';
      case 'monthly':
        return 'Every Month';
      default:
        return r;
    }
  }
}