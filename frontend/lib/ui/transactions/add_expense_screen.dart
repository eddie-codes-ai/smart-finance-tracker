// lib/ui/transactions/add_expense_screen.dart
// Form screen to log a new expense record.
// UPDATED: Categories are now loaded dynamically from the backend.
// Users can add custom categories via the + tile at the end of the grid.
// Custom categories can be deleted with a long press.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../core/constants.dart';
import '../../data/remote/api_client.dart';
import '../../models/user_category_model.dart';
import '../../providers/expense_provider.dart';
import '../../providers/budget_provider.dart';
import '../../providers/analysis_provider.dart';

class AddExpenseScreen extends StatefulWidget {
  const AddExpenseScreen({super.key});

  @override
  State<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends State<AddExpenseScreen> {
  final _formKey               = GlobalKey<FormState>();
  final _amountController      = TextEditingController();
  final _descriptionController = TextEditingController();

  String  _selectedCategory    = 'Food';
  String  _selectedExpenseType = 'daily';
  String? _selectedRecurrence;

  // Categories loaded from backend (defaults + custom)
  List<UserCategoryModel> _categories = [];
  bool _categoriesLoading = true;

  static const Map<String, IconData> _categoryIcons = {
    'Food':          Icons.restaurant_outlined,
    'Transport':     Icons.directions_bus_outlined,
    'Entertainment': Icons.movie_outlined,
    'Shopping':      Icons.shopping_bag_outlined,
    'Health':        Icons.local_hospital_outlined,
    'Education':     Icons.school_outlined,
    'Utilities':     Icons.bolt_outlined,
    'Rent':          Icons.home_outlined,
    'Other':         Icons.category_outlined,
  };

  static const List<String> _recurrenceOptions = [
    'daily', 'weekly', 'biweekly', 'monthly',
  ];

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    setState(() => _categoriesLoading = true);
    try {
      final data = await ApiClient.getCategories();
      if (data['status'] == 'success') {
        setState(() {
          _categories = (data['categories'] as List)
              .map((e) => UserCategoryModel.fromJson(e))
              .toList();
        });
      }
    } catch (_) {
      // Fallback to hardcoded defaults if API fails
      setState(() {
        _categories = AppConstants.expenseCategories
            .map((c) => UserCategoryModel.defaultCategory(c))
            .toList();
      });
    } finally {
      setState(() => _categoriesLoading = false);
    }
  }

  void _showAddCategoryDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Category'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            hintText: 'e.g. Gym, Pets, Medical...',
            prefixIcon: Icon(Icons.label_outline),
          ),
          onSubmitted: (_) => _submitNewCategory(ctx, controller.text),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => _submitNewCategory(ctx, controller.text),
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _submitNewCategory(BuildContext ctx, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;

    Navigator.pop(ctx);

    try {
      final data = await ApiClient.addCategory(trimmed);
      if (!mounted) return;
      if (data['status'] == 'success') {
        final newCat = UserCategoryModel.fromJson(data['category']);
        setState(() {
          _categories.add(newCat);
          _selectedCategory = newCat.name;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Category "${newCat.name}" added.'),
            backgroundColor: AppTheme.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data['message'] ?? 'Failed to add category.'),
            backgroundColor: AppTheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to add category. Check your connection.'),
          backgroundColor: AppTheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _deleteCustomCategory(UserCategoryModel cat) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Category'),
        content: Text(
            'Delete "${cat.name}"? Existing expenses with this category will not be affected.'),
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

    if (confirm != true) return;

    try {
      final data = await ApiClient.deleteCategory(cat.name);
      if (!mounted) return;
      if (data['status'] == 'success') {
        setState(() {
          _categories.removeWhere((c) => c.name == cat.name);
          if (_selectedCategory == cat.name) _selectedCategory = 'Food';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Category "${cat.name}" deleted.'),
            backgroundColor: AppTheme.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data['message'] ?? 'Failed to delete category.'),
            backgroundColor: AppTheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to delete category. Check your connection.'),
          backgroundColor: AppTheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    final recurrence = _selectedExpenseType == 'recurring'
        ? _selectedRecurrence
        : null;

    final double? budgetLimit =
        context.read<BudgetProvider>().limitFor(_selectedCategory);

    final expenseProvider  = context.read<ExpenseProvider>();
    final analysisProvider = context.read<AnalysisProvider>();

    final success = await expenseProvider.addExpense(
      amount:             double.parse(_amountController.text.trim()),
      category:           _selectedCategory,
      description:        _descriptionController.text.trim(),
      expenseType:        _selectedExpenseType,
      recurrenceInterval: recurrence,
      budgetLimit:        budgetLimit,
    );

    if (!mounted) return;

    if (success) {
      final now = DateTime.now();
      await Future.wait([
        expenseProvider.fetchExpenses(month: now.month, year: now.year),
        analysisProvider.analyze(month: now.month, year: now.year),
      ]);
      if (!mounted) return;
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
          content: Text(
              expenseProvider.errorMessage ?? 'Failed to add expense.'),
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
              Row(
                children: [
                  const Text('Category',
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textSecondary,
                          fontSize: 13)),
                  const Spacer(),
                  if (!_categoriesLoading)
                    Text(
                      'Long press custom to delete',
                      style: TextStyle(
                          fontSize: 10,
                          color: AppTheme.textSecondary.withOpacity(0.7),
                          fontStyle: FontStyle.italic),
                    ),
                ],
              ),
              const SizedBox(height: 8),

              _categoriesLoading
                  ? const Center(
                      child: Padding(
                      padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator(
                          color: AppTheme.primary),
                    ))
                  : GridView.count(
                      crossAxisCount: 3,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                      childAspectRatio: 2.2,
                      children: [
                        // Existing categories
                        ..._categories.map((cat) {
                          final isSelected = _selectedCategory == cat.name;
                          return GestureDetector(
                            onTap: () => setState(
                                () => _selectedCategory = cat.name),
                            onLongPress: cat.isCustom
                                ? () => _deleteCustomCategory(cat)
                                : null,
                            child: Container(
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? AppTheme.primary
                                    : AppTheme.surface,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isSelected
                                      ? AppTheme.primary
                                      : cat.isCustom
                                          ? AppTheme.primary.withOpacity(0.4)
                                          : AppTheme.divider,
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    _categoryIcons[cat.name] ??
                                        Icons.label_outlined,
                                    size: 14,
                                    color: isSelected
                                        ? Colors.white
                                        : cat.isCustom
                                            ? AppTheme.primary
                                            : AppTheme.textSecondary,
                                  ),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      cat.name,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: isSelected
                                            ? Colors.white
                                            : AppTheme.textPrimary,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),

                        // + Add Category tile
                        GestureDetector(
                          onTap: _showAddCategoryDialog,
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppTheme.surface,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: AppTheme.primary.withOpacity(0.4),
                                style: BorderStyle.solid,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.add,
                                    size: 14, color: AppTheme.primary),
                                const SizedBox(width: 4),
                                Text(
                                  'Add',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
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

              // ── Recurrence Interval ──────────────────────────────────────
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
                          width: 20, height: 20,
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
      case 'daily':     return 'Daily';
      case 'monthly':   return 'Monthly';
      case 'one-time':  return 'One-Time';
      case 'recurring': return 'Recurring';
      default:          return type;
    }
  }

  String _recurrenceLabel(String r) {
    switch (r) {
      case 'daily':    return 'Every Day';
      case 'weekly':   return 'Every Week';
      case 'biweekly': return 'Every 2 Weeks';
      case 'monthly':  return 'Every Month';
      default:         return r;
    }
  }
}