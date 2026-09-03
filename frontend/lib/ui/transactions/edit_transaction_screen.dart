// lib/ui/transactions/edit_transaction_screen.dart
//
// Edits an existing expense or income record in place via PUT.
//
// This screen used to save by deleting the record and creating a replacement,
// which was not atomic (a failed re-create lost the record) and reset the date
// to today. It now sends a partial update: only the fields the user actually
// changed are transmitted, and anything untouched — including the original
// timestamp — is preserved server-side.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../core/constants.dart';
import '../../providers/expense_provider.dart';
import '../../providers/income_provider.dart';
import '../../providers/analysis_provider.dart';
import '../../models/expense_model.dart';
import '../../models/income_model.dart';

class EditTransactionScreen extends StatefulWidget {
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
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _amountController;
  late TextEditingController _descController;
  late String _selectedCategory;
  late String _selectedIncomeType;
  late String _selectedExpenseType;

  /// The record's timestamp. Editing the date replaces only the calendar day
  /// and keeps the original time, so a transaction never shifts across a day
  /// boundary just because it was edited.
  late DateTime _selectedDate;
  late DateTime _originalDate;

  bool _saving = false;

  bool get _isExpense => widget.expense != null;

  static const _incomeTypes = ['monthly', 'helb', 'parental', 'gig', 'daily', 'other'];

  @override
  void initState() {
    super.initState();
    if (_isExpense) {
      final e = widget.expense!;
      _amountController    = TextEditingController(text: e.amount.toStringAsFixed(2));
      _descController      = TextEditingController(text: e.description);
      _selectedCategory    = e.category;
      _selectedExpenseType = AppConstants.expenseTypes.contains(e.expenseType)
          ? e.expenseType
          : AppConstants.expenseTypes.first;
      _selectedIncomeType  = 'other';
      _originalDate        = DateTime.tryParse(e.dateAdded) ?? DateTime.now();
    } else {
      final i = widget.income!;
      _amountController    = TextEditingController(text: i.amount.toStringAsFixed(2));
      _descController      = TextEditingController(text: i.description);
      _selectedCategory    = 'Other';
      _selectedExpenseType = AppConstants.expenseTypes.first;
      _selectedIncomeType  = i.incomeType;
      _originalDate        = DateTime.tryParse(i.dateAdded) ?? DateTime.now();
    }
    _selectedDate = _originalDate;
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descController.dispose();
    super.dispose();
  }

  bool get _dateChanged =>
      !_selectedDate.isAtSameMomentAs(_originalDate);

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context:   context,
      initialDate: _selectedDate.isAfter(DateTime.now()) ? DateTime.now() : _selectedDate,
      firstDate: DateTime(2020),
      lastDate:  DateTime.now(),
      helpText:  'Transaction date',
    );
    if (picked == null) return;
    setState(() {
      // Keep the original time of day — only the calendar date moves.
      _selectedDate = DateTime(
        picked.year, picked.month, picked.day,
        _originalDate.hour, _originalDate.minute, _originalDate.second,
        _originalDate.millisecond, _originalDate.microsecond,
      );
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    // Captured before any await so the snackbar and pop don't reach for a
    // context that may no longer be mounted.
    final messenger      = ScaffoldMessenger.of(context);
    final navigator      = Navigator.of(context);
    final analysis       = context.read<AnalysisProvider>();
    final expenseStore   = context.read<ExpenseProvider>();
    final incomeStore    = context.read<IncomeProvider>();

    final newAmount = double.parse(_amountController.text.trim());
    final newDesc   = _descController.text.trim();
    final newDate   = _dateChanged ? _selectedDate : null;
    final now       = DateTime.now();

    final bool saved;
    final String? failure;

    if (_isExpense) {
      saved = await expenseStore.updateExpense(
        id:          widget.expense!.id,
        amount:      newAmount,
        category:    _selectedCategory,
        description: newDesc,
        expenseType: _selectedExpenseType,
        dateAdded:   newDate,
      );
      failure = expenseStore.errorMessage;
    } else {
      saved = await incomeStore.updateIncome(
        id:          widget.income!.id,
        amount:      newAmount,
        incomeType:  _selectedIncomeType,
        description: newDesc,
        dateAdded:   newDate,
      );
      failure = incomeStore.errorMessage;
    }

    if (!mounted) return;

    // The record is untouched on the server — stay on the form so the user can
    // retry or correct the input, and never claim the edit succeeded.
    if (!saved) {
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(
          content: Text(failure ?? 'Could not save your changes.'),
          backgroundColor: AppTheme.error));
      return;
    }

    await Future.wait([
      if (_isExpense)
        expenseStore.fetchExpenses(month: now.month, year: now.year)
      else
        incomeStore.fetchIncome(month: now.month, year: now.year),
      analysis.analyze(month: now.month, year: now.year),
    ]);

    if (mounted) setState(() => _saving = false);

    navigator.pop(true);
    messenger.showSnackBar(SnackBar(
        content: Text(_isExpense ? 'Expense updated.' : 'Income updated.'),
        backgroundColor: AppTheme.primary));
  }

  @override
  Widget build(BuildContext context) {
    final cs      = Theme.of(context).colorScheme;
    final divider = Theme.of(context).dividerColor;

    return Scaffold(
      appBar: AppBar(title: Text(_isExpense ? 'Edit Expense' : 'Edit Income')),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [

              // ── Amount ────────────────────────────────────────────────────
              _sectionLabel('Amount (KES)', cs),
              const SizedBox(height: 8),
              TextFormField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(prefixText: 'KES  ', hintText: '0.00'),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Amount is required';
                  final parsed = double.tryParse(v.trim());
                  if (parsed == null || parsed <= 0) return 'Enter a valid amount';
                  return null;
                },
              ),

              const SizedBox(height: 20),

              // ── Description ───────────────────────────────────────────────
              _sectionLabel('Description', cs),
              const SizedBox(height: 8),
              TextFormField(controller: _descController, maxLines: 2,
                  decoration: const InputDecoration(hintText: 'What was this for?')),

              const SizedBox(height: 20),

              // ── Date ──────────────────────────────────────────────────────
              _sectionLabel('Date', cs),
              const SizedBox(height: 8),
              InkWell(
                onTap: _saving ? null : _pickDate,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _dateChanged ? AppTheme.primary : divider),
                  ),
                  child: Row(children: [
                    Icon(Icons.calendar_today_outlined, size: 17,
                        color: cs.onSurface.withOpacity(0.55)),
                    const SizedBox(width: 12),
                    Expanded(child: Text(
                        DateFormat('EEE, d MMM yyyy').format(_selectedDate),
                        style: TextStyle(fontSize: 14.5, color: cs.onSurface))),
                    if (_dateChanged)
                      TextButton(
                        onPressed: () => setState(() => _selectedDate = _originalDate),
                        child: const Text('Reset'),
                      )
                    else
                      const Text('Change', style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.primary)),
                  ]),
                ),
              ),

              const SizedBox(height: 20),

              // ── Category (expenses only) ──────────────────────────────────
              if (_isExpense) ...[
                _sectionLabel('Category', cs),
                const SizedBox(height: 10),
                _chips(
                  values:   AppConstants.expenseCategories,
                  selected: _selectedCategory,
                  onTap:    (v) => setState(() => _selectedCategory = v),
                  cs:       cs,
                  divider:  divider,
                ),
                const SizedBox(height: 20),

                // ── Expense type ────────────────────────────────────────────
                _sectionLabel('Type', cs),
                const SizedBox(height: 4),
                Text(
                  'One-time expenses are left out of your spending totals and health score.',
                  style: TextStyle(fontSize: 11.5, color: cs.onSurface.withOpacity(0.5)),
                ),
                const SizedBox(height: 10),
                _chips(
                  values:   AppConstants.expenseTypes,
                  selected: _selectedExpenseType,
                  onTap:    (v) => setState(() => _selectedExpenseType = v),
                  cs:       cs,
                  divider:  divider,
                  upperCase: true,
                ),
                const SizedBox(height: 20),
              ],

              // ── Income type (income only) ─────────────────────────────────
              if (!_isExpense) ...[
                _sectionLabel('Income type', cs),
                const SizedBox(height: 10),
                _chips(
                  values:   _incomeTypes,
                  selected: _selectedIncomeType,
                  onTap:    (v) => setState(() => _selectedIncomeType = v),
                  cs:       cs,
                  divider:  divider,
                  upperCase: true,
                ),
                const SizedBox(height: 20),
              ],

              const SizedBox(height: 12),

              // ── Save button ───────────────────────────────────────────────
              ElevatedButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.check),
                label: Text(_saving ? 'Saving...' : 'Save changes'),
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
              ),

              const SizedBox(height: 12),

              OutlinedButton(
                onPressed: _saving ? null : () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Selectable pill row — the same visual language the category and income
  /// type pickers already used.
  Widget _chips({
    required List<String> values,
    required String selected,
    required ValueChanged<String> onTap,
    required ColorScheme cs,
    required Color divider,
    bool upperCase = false,
  }) {
    return Wrap(
      spacing: 8, runSpacing: 8,
      children: values.map((value) {
        final isSelected = value == selected;
        return GestureDetector(
          onTap: () => onTap(value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: isSelected ? AppTheme.primary : cs.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: isSelected ? AppTheme.primary : divider),
            ),
            child: Text(
              upperCase ? value.toUpperCase() : value,
              style: TextStyle(
                fontSize: upperCase ? 12 : 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected ? Colors.white : cs.onSurface,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _sectionLabel(String text, ColorScheme cs) {
    return Text(text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
        color: cs.onSurface.withOpacity(0.6)));
  }
}
