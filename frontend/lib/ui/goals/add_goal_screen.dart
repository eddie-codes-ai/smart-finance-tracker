// lib/ui/goals/add_goal_screen.dart
// Form to create a new savings goal.
// Fields: name, goal_amount, due_date (date picker).
// due_date is sent as "YYYY-MM-DD" matching the backend's strptime format.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../core/constants.dart';
import '../../providers/goals_provider.dart';

class AddGoalScreen extends StatefulWidget {
  const AddGoalScreen({super.key});

  @override
  State<AddGoalScreen> createState() => _AddGoalScreenState();
}

class _AddGoalScreenState extends State<AddGoalScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _amountController = TextEditingController();
  DateTime? _dueDate;

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 30)),
      firstDate: now,
      lastDate: DateTime(now.year + 5),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppTheme.primary,
            onPrimary: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() => _dueDate = picked);
    }
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    if (_dueDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a due date for your goal.'),
          backgroundColor: AppTheme.warning,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final provider = context.read<GoalsProvider>();
    final success = await provider.addGoal(
      name: _nameController.text.trim(),
      goalAmount: double.parse(_amountController.text.trim()),
      // Backend expects "YYYY-MM-DD" format from strptime.
      dueDate: DateFormat('yyyy-MM-dd').format(_dueDate!),
    );

    if (!mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Savings goal created!'),
          backgroundColor: AppTheme.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(provider.errorMessage ?? 'Failed to create goal.'),
          backgroundColor: AppTheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = context.watch<GoalsProvider>().isLoading;
    final dateFmt = DateFormat('dd MMMM yyyy');

    return Scaffold(
      appBar: AppBar(title: const Text('New Savings Goal')),
      backgroundColor: AppTheme.background,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Goal Name ────────────────────────────────────────────────
              const Text('Goal Name',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary,
                      fontSize: 13)),
              const SizedBox(height: 8),
              TextFormField(
                controller: _nameController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  hintText: 'e.g. Laptop, Rent Deposit, Emergency Fund...',
                  prefixIcon: Icon(Icons.flag_outlined),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please give your goal a name.';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 24),

              // ── Target Amount ────────────────────────────────────────────
              const Text('Target Amount (KES)',
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
                    return 'Please enter a target amount.';
                  }
                  if (double.tryParse(value) == null ||
                      double.parse(value) <= 0) {
                    return 'Please enter a valid amount greater than 0.';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 8),

              // Quick amount chips
              Wrap(
                spacing: 8,
                children: [5000, 10000, 20000, 50000, 100000]
                    .map(
                      (amt) => ActionChip(
                        label: Text('${AppConstants.currency} $amt'),
                        onPressed: () => setState(() =>
                            _amountController.text = amt.toString()),
                        backgroundColor: AppTheme.surface,
                        labelStyle: const TextStyle(
                            fontSize: 12, color: AppTheme.primary),
                        side: const BorderSide(color: AppTheme.primary),
                      ),
                    )
                    .toList(),
              ),

              const SizedBox(height: 24),

              // ── Due Date ─────────────────────────────────────────────────
              const Text('Target Date',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary,
                      fontSize: 13)),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: _pickDate,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.divider),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today_outlined,
                          color: AppTheme.textSecondary, size: 20),
                      const SizedBox(width: 12),
                      Text(
                        _dueDate != null
                            ? dateFmt.format(_dueDate!)
                            : 'Select a target date',
                        style: TextStyle(
                          fontSize: 14,
                          color: _dueDate != null
                              ? AppTheme.textPrimary
                              : AppTheme.textSecondary,
                        ),
                      ),
                      const Spacer(),
                      const Icon(Icons.chevron_right,
                          color: AppTheme.textSecondary),
                    ],
                  ),
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
                  label: Text(isLoading ? 'Saving...' : 'Create Goal'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}