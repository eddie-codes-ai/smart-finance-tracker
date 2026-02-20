// lib/ui/budget/add_budget_screen.dart
// Form to set or update a spending limit for a category.
// Can be opened two ways:
//   1. From "Set / Update a Budget" button — no pre-filled values
//   2. By tapping a category card — category and limit pre-filled for editing
// Backend uses upsert pattern so create and update are the same API call.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../core/constants.dart';
import '../../providers/budget_provider.dart';

class AddBudgetScreen extends StatefulWidget {
  const AddBudgetScreen({super.key});

  @override
  State<AddBudgetScreen> createState() => _AddBudgetScreenState();
}

class _AddBudgetScreenState extends State<AddBudgetScreen> {
  final _formKey = GlobalKey<FormState>();
  final _limitController = TextEditingController();
  String _selectedCategory = 'Food';
  bool _argsLoaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Load route arguments on first build only.
    if (!_argsLoaded) {
      _argsLoaded = true;
      final args =
          ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
      if (args != null) {
        if (args['category'] != null) {
          _selectedCategory = args['category'] as String;
        }
        if (args['currentLimit'] != null) {
          _limitController.text =
              (args['currentLimit'] as double).toStringAsFixed(0);
        }
      }
    }
  }

  @override
  void dispose() {
    _limitController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    final now = DateTime.now();
    final monthYear =
        '${now.year}-${now.month.toString().padLeft(2, '0')}';

    final provider = context.read<BudgetProvider>();
    final success = await provider.setBudget(
      category: _selectedCategory,
      limit: double.parse(_limitController.text.trim()),
      monthYear: monthYear,
    );

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? 'Budget for $_selectedCategory saved.'
              : provider.errorMessage ?? 'Failed to save budget.',
        ),
        backgroundColor: success ? AppTheme.success : AppTheme.error,
        behavior: SnackBarBehavior.floating,
      ),
    );

    if (success) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = context.watch<BudgetProvider>().isLoading;
    final now = DateTime.now();
    final monthLabel = DateFormat('MMMM yyyy').format(now);

    return Scaffold(
      appBar: AppBar(title: const Text('Set Budget Limit')),
      backgroundColor: AppTheme.background,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Month indicator ──────────────────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: AppTheme.primary.withOpacity(0.2)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today_outlined,
                        size: 16, color: AppTheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      'Setting budget for $monthLabel',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primary,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // ── Category dropdown ────────────────────────────────────────
              const Text(
                'Category',
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary,
                    fontSize: 13),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _selectedCategory,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.category_outlined),
                ),
                items: AppConstants.expenseCategories
                    .map((cat) => DropdownMenuItem(
                          value: cat,
                          child: Text(cat),
                        ))
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _selectedCategory = value);
                  }
                },
              ),

              const SizedBox(height: 24),

              // ── Limit amount ─────────────────────────────────────────────
              const Text(
                'Monthly Spending Limit (KES)',
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary,
                    fontSize: 13),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _limitController,
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
                    return 'Please enter a limit.';
                  }
                  if (double.tryParse(value) == null ||
                      double.parse(value) <= 0) {
                    return 'Please enter a valid limit greater than 0.';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 12),

              // ── Quick amount chips ────────────────────────────────────────
              const Text(
                'Quick amounts:',
                style:
                    TextStyle(fontSize: 12, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [500, 1000, 2000, 3000, 5000, 10000]
                    .map(
                      (amt) => ActionChip(
                        label: Text('${AppConstants.currency} $amt'),
                        onPressed: () => setState(
                            () => _limitController.text = amt.toString()),
                        backgroundColor: AppTheme.surface,
                        labelStyle: const TextStyle(
                            fontSize: 12, color: AppTheme.primary),
                        side: const BorderSide(color: AppTheme.primary),
                      ),
                    )
                    .toList(),
              ),

              const SizedBox(height: 32),

              // ── Submit button ────────────────────────────────────────────
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
                  label: Text(isLoading ? 'Saving...' : 'Save Budget'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}