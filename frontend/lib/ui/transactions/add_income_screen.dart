// lib/ui/transactions/add_income_screen.dart
// UPDATED: Full dark mode support.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../core/constants.dart';
import '../../data/remote/api_client.dart';
import '../../models/user_category_model.dart';
import '../../providers/income_provider.dart';
import '../../providers/analysis_provider.dart';

class AddIncomeScreen extends StatefulWidget {
  const AddIncomeScreen({super.key});
  @override
  State<AddIncomeScreen> createState() => _AddIncomeScreenState();
}

class _AddIncomeScreenState extends State<AddIncomeScreen> {
  final _formKey               = GlobalKey<FormState>();
  final _amountController      = TextEditingController();
  final _descriptionController = TextEditingController();

  String _selectedType = 'monthly';
  List<UserCategoryModel> _incomeTypes = [];
  bool _typesLoading = true;

  @override
  void initState() {
    super.initState();
    _loadIncomeTypes();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadIncomeTypes() async {
    setState(() => _typesLoading = true);
    try {
      final data = await ApiClient.getIncomeTypes();
      if (data['status'] == 'success') {
        setState(() {
          _incomeTypes = (data['income_types'] as List)
              .map((e) => UserCategoryModel.fromJson(e)).toList();
        });
      }
    } catch (_) {
      setState(() {
        _incomeTypes = AppConstants.incomeTypes
            .map((t) => UserCategoryModel.defaultCategory(t)).toList();
      });
    } finally {
      setState(() => _typesLoading = false);
    }
  }

  void _showAddTypeDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Income Type'),
        content: TextField(controller: controller, autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
                hintText: 'e.g. Freelance, Business, Scholarship...',
                prefixIcon: Icon(Icons.label_outline)),
            onSubmitted: (_) => _submitNewType(ctx, controller.text)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => _submitNewType(ctx, controller.text), child: const Text('Add')),
        ],
      ),
    );
  }

  Future<void> _submitNewType(BuildContext ctx, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    Navigator.pop(ctx);
    try {
      final data = await ApiClient.addIncomeType(trimmed);
      if (!mounted) return;
      if (data['status'] == 'success') {
        final newType = UserCategoryModel.fromJson(data['income_type']);
        setState(() { _incomeTypes.add(newType); _selectedType = newType.name; });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Income type "${newType.name}" added.'),
            backgroundColor: AppTheme.success, behavior: SnackBarBehavior.floating));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(data['message'] ?? 'Failed to add income type.'),
            backgroundColor: AppTheme.error, behavior: SnackBarBehavior.floating));
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Failed to add income type. Check your connection.'),
          backgroundColor: AppTheme.error, behavior: SnackBarBehavior.floating));
    }
  }

  Future<void> _deleteCustomType(UserCategoryModel type) async {
    final confirm = await showDialog<bool>(context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Delete Income Type'),
          content: Text('Delete "${type.name}"? Existing income records with this type will not be affected.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(ctx, true),
                style: TextButton.styleFrom(foregroundColor: AppTheme.error), child: const Text('Delete')),
          ],
        ));
    if (confirm != true) return;
    try {
      final data = await ApiClient.deleteIncomeType(type.name);
      if (!mounted) return;
      if (data['status'] == 'success') {
        setState(() {
          _incomeTypes.removeWhere((t) => t.name == type.name);
          if (_selectedType == type.name) _selectedType = 'monthly';
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Income type "${type.name}" deleted.'),
            backgroundColor: AppTheme.success, behavior: SnackBarBehavior.floating));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(data['message'] ?? 'Failed to delete income type.'),
            backgroundColor: AppTheme.error, behavior: SnackBarBehavior.floating));
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Failed to delete income type. Check your connection.'),
          backgroundColor: AppTheme.error, behavior: SnackBarBehavior.floating));
    }
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    final incomeProvider   = context.read<IncomeProvider>();
    final analysisProvider = context.read<AnalysisProvider>();
    final success = await incomeProvider.addIncome(
      amount: double.parse(_amountController.text.trim()),
      incomeType: _selectedType,
      description: _descriptionController.text.trim(),
    );
    if (!mounted) return;
    if (success) {
      final now = DateTime.now();
      await Future.wait([
        incomeProvider.fetchIncome(month: now.month, year: now.year),
        analysisProvider.analyze(month: now.month, year: now.year),
      ]);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Income added successfully.'),
          backgroundColor: AppTheme.success, behavior: SnackBarBehavior.floating));
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(incomeProvider.errorMessage ?? 'Failed to add income.'),
          backgroundColor: AppTheme.error, behavior: SnackBarBehavior.floating));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = context.watch<IncomeProvider>().isLoading;
    final cs = Theme.of(context).colorScheme;
    final dividerColor = Theme.of(context).dividerColor;

    return Scaffold(
      appBar: AppBar(title: const Text('Add Income')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Amount ──────────────────────────────────────────────────
              Text('Amount (KES)', style: TextStyle(fontWeight: FontWeight.w600,
                  color: cs.onSurface.withOpacity(0.6), fontSize: 13)),
              const SizedBox(height: 8),
              TextFormField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
                decoration: const InputDecoration(hintText: '0.00',
                    prefixIcon: Icon(Icons.attach_money), prefixText: 'KES  '),
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                validator: (value) {
                  if (value == null || value.isEmpty) return 'Please enter an amount.';
                  if (double.tryParse(value) == null || double.parse(value) <= 0) {
                    return 'Please enter a valid amount greater than 0.';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 24),

              // ── Income Type ──────────────────────────────────────────────
              Row(children: [
                Text('Income Type', style: TextStyle(fontWeight: FontWeight.w600,
                    color: cs.onSurface.withOpacity(0.6), fontSize: 13)),
                const Spacer(),
                if (!_typesLoading)
                  Text('Long press custom to delete', style: TextStyle(
                      fontSize: 10, color: cs.onSurface.withOpacity(0.4), fontStyle: FontStyle.italic)),
              ]),
              const SizedBox(height: 8),

              _typesLoading
                  ? const Center(child: Padding(padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator(color: AppTheme.primary)))
                  : Wrap(
                      spacing: 8, runSpacing: 8,
                      children: [
                        ..._incomeTypes.map((type) {
                          final isSelected = _selectedType == type.name;
                          return GestureDetector(
                            onTap: () => setState(() => _selectedType = type.name),
                            onLongPress: type.isCustom ? () => _deleteCustomType(type) : null,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: isSelected ? AppTheme.primary : cs.surface,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: isSelected
                                    ? AppTheme.primary
                                    : type.isCustom
                                        ? AppTheme.primary.withOpacity(0.4)
                                        : dividerColor),
                              ),
                              child: Text(_typeLabel(type.name), style: TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w600,
                                  color: isSelected
                                      ? Colors.white
                                      : type.isCustom ? AppTheme.primary : cs.onSurface)),
                            ),
                          );
                        }),
                        // + Add chip
                        GestureDetector(
                          onTap: _showAddTypeDialog,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: cs.surface, borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: AppTheme.primary.withOpacity(0.4)),
                            ),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.add, size: 14, color: AppTheme.primary),
                              const SizedBox(width: 4),
                              Text('Add', style: TextStyle(fontSize: 13,
                                  fontWeight: FontWeight.w600, color: AppTheme.primary)),
                            ]),
                          ),
                        ),
                      ],
                    ),

              const SizedBox(height: 24),

              // ── Description ──────────────────────────────────────────────
              Text('Description (optional)', style: TextStyle(fontWeight: FontWeight.w600,
                  color: cs.onSurface.withOpacity(0.6), fontSize: 13)),
              const SizedBox(height: 8),
              TextFormField(
                controller: _descriptionController,
                textInputAction: TextInputAction.done, maxLength: 100,
                decoration: const InputDecoration(
                    hintText: 'e.g. HELB disbursement, January stipend...',
                    prefixIcon: Icon(Icons.notes_outlined)),
              ),

              const SizedBox(height: 32),

              // ── Submit ───────────────────────────────────────────────────
              SizedBox(
                width: double.infinity, height: 52,
                child: ElevatedButton.icon(
                  onPressed: isLoading ? null : _submit,
                  icon: isLoading
                      ? const SizedBox(width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check),
                  label: Text(isLoading ? 'Saving...' : 'Save Income Record'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'monthly':  return 'Monthly';
      case 'daily':    return 'Daily';
      case 'helb':     return 'HELB';
      case 'parental': return 'Parental';
      case 'gig':      return 'Gig';
      case 'other':    return 'Other';
      default:         return type;
    }
  }
}