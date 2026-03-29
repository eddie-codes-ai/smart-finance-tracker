// lib/ui/transactions/edit_transaction_screen.dart
//
// Edit screen for both income and expense records.
//
// Strategy: delete the old record + create a new one with updated values.
// This avoids needing a PUT/PATCH backend endpoint.
//
// Editable fields:
//   Expense  — amount, description, category
//   Income   — amount, description, income type

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../core/constants.dart';
import '../../providers/expense_provider.dart';
import '../../providers/income_provider.dart';
import '../../models/expense_model.dart';
import '../../models/income_model.dart';

class EditTransactionScreen extends StatefulWidget {
  // Pass either an expense or income — never both.
  final ExpenseModel? expense;
  final IncomeModel?  income;

  const EditTransactionScreen.expense({super.key, required ExpenseModel this.expense})
      : income = null;

  const EditTransactionScreen.income({super.key, required IncomeModel this.income})
      : expense = null;

  @override
  State<EditTransactionScreen> createState() => _EditTransactionScreenState();
}

class _EditTransactionScreenState extends State<EditTransactionScreen> {
  final _formKey   = GlobalKey<FormState>();
  late TextEditingController _amountController;
  late TextEditingController _descController;
  late String _selectedCategory;
  late String _selectedIncomeType;
  bool _saving = false;

  bool get _isExpense => widget.expense != null;

  static const _incomeTypes = [
    'monthly', 'helb', 'parental', 'gig', 'daily', 'other'
  ];

  @override
  void initState() {
    super.initState();
    if (_isExpense) {
      final e = widget.expense!;
      _amountController    = TextEditingController(text: e.amount.toStringAsFixed(2));
      _descController      = TextEditingController(text: e.description);
      _selectedCategory    = e.category;
      _selectedIncomeType  = 'other';
    } else {
      final i = widget.income!;
      _amountController    = TextEditingController(text: i.amount.toStringAsFixed(2));
      _descController      = TextEditingController(text: i.description);
      _selectedCategory    = 'Other';
      _selectedIncomeType  = i.incomeType;
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      final newAmount = double.parse(_amountController.text.trim());
      final newDesc   = _descController.text.trim();

      if (_isExpense) {
        final e = widget.expense!;
        // Delete old record
        await context.read<ExpenseProvider>().deleteExpense(e.id);
        // Create updated record
        await context.read<ExpenseProvider>().addExpense(
          amount:      newAmount,
          category:    _selectedCategory,
          description: newDesc,
          expenseType: e.expenseType,
        );
      } else {
        final i = widget.income!;
        await context.read<IncomeProvider>().deleteIncome(i.id);
        await context.read<IncomeProvider>().addIncome(
          amount:      newAmount,
          incomeType:  _selectedIncomeType,
          description: newDesc,
        );
      }

      if (!mounted) return;
      Navigator.pop(context, true); // true = was edited
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isExpense
              ? 'Expense updated successfully.'
              : 'Income updated successfully.'),
          backgroundColor: AppTheme.primary,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save changes: ${e.toString()}'),
          backgroundColor: AppTheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isExpense ? 'Edit Expense' : 'Edit Income'),
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [

              // ── Info banner ───────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppTheme.info.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: AppTheme.info.withOpacity(0.25)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline,
                        size: 16, color: AppTheme.info),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Changes are saved by deleting the old record and '
                        'creating a new one. The date will reset to today.',
                        style: TextStyle(
                            fontSize: 12, color: AppTheme.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // ── Amount ────────────────────────────────────────────────────
              _sectionLabel('Amount (KES)'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true),
                decoration: const InputDecoration(
                  prefixText: 'KES  ',
                  hintText: '0.00',
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Amount is required';
                  }
                  if (double.tryParse(v.trim()) == null ||
                      double.parse(v.trim()) <= 0) {
                    return 'Enter a valid amount';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 20),

              // ── Description ───────────────────────────────────────────────
              _sectionLabel('Description'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _descController,
                maxLines: 2,
                decoration: const InputDecoration(
                  hintText: 'What was this for?',
                ),
              ),

              const SizedBox(height: 20),

              // ── Category (expenses only) ──────────────────────────────────
              if (_isExpense) ...[
                _sectionLabel('Category'),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: AppConstants.expenseCategories.map((cat) {
                    final selected = cat == _selectedCategory;
                    return GestureDetector(
                      onTap: () =>
                          setState(() => _selectedCategory = cat),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 9),
                        decoration: BoxDecoration(
                          color: selected
                              ? AppTheme.primary
                              : AppTheme.surface,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: selected
                                ? AppTheme.primary
                                : AppTheme.divider,
                          ),
                          boxShadow: selected
                              ? []
                              : [
                                  BoxShadow(
                                    color:
                                        Colors.black.withOpacity(0.04),
                                    blurRadius: 4,
                                    offset: const Offset(0, 1),
                                  )
                                ],
                        ),
                        child: Text(
                          cat,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: selected
                                ? FontWeight.w600
                                : FontWeight.normal,
                            color: selected
                                ? Colors.white
                                : AppTheme.textPrimary,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),
              ],

              // ── Income type (income only) ─────────────────────────────────
              if (!_isExpense) ...[
                _sectionLabel('Income type'),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _incomeTypes.map((type) {
                    final selected = type == _selectedIncomeType;
                    return GestureDetector(
                      onTap: () =>
                          setState(() => _selectedIncomeType = type),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 9),
                        decoration: BoxDecoration(
                          color: selected
                              ? AppTheme.primary
                              : AppTheme.surface,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: selected
                                ? AppTheme.primary
                                : AppTheme.divider,
                          ),
                        ),
                        child: Text(
                          type.toUpperCase(),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: selected
                                ? FontWeight.w600
                                : FontWeight.normal,
                            color: selected
                                ? Colors.white
                                : AppTheme.textPrimary,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),
              ],

              const SizedBox(height: 12),

              // ── Save button ───────────────────────────────────────────────
              ElevatedButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.check),
                label: Text(_saving ? 'Saving...' : 'Save changes'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),

              const SizedBox(height: 12),

              OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppTheme.textSecondary,
      ),
    );
  }
}