// lib/ui/goals/goals_screen.dart
// Lists all active savings goals with progress toward each.
// Progress is based on explicit contributions, not net savings.
// Each goal card shows: Contributed | Still Needed | Add Contribution button.
// After a contribution is added, analysis is re-run automatically so the
// dashboard score and balance update without a manual pull-to-refresh.
// Swipe left to mark complete, FAB to add a new goal.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../core/constants.dart';
import '../../core/routes.dart';
import '../../providers/goals_provider.dart';
import '../../providers/analysis_provider.dart';
import '../../models/savings_goal_model.dart';

class GoalsScreen extends StatefulWidget {
  const GoalsScreen({super.key});

  @override
  State<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends State<GoalsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<GoalsProvider>().fetchGoals();
    });
  }

  @override
  Widget build(BuildContext context) {
    final goals = context.watch<GoalsProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Savings Goals')),
      backgroundColor: AppTheme.background,
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.pushNamed(context, AppRoutes.addGoal)
            .then((_) => goals.fetchGoals()),
        tooltip: 'Add Goal',
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        onRefresh: () => goals.fetchGoals(),
        color: AppTheme.primary,
        child: goals.isLoading
            ? const Center(
                child: CircularProgressIndicator(color: AppTheme.primary))
            : goals.goals.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                    itemCount: goals.goals.length,
                    itemBuilder: (context, index) {
                      return _buildGoalCard(goals.goals[index], goals);
                    },
                  ),
      ),
    );
  }

  Widget _buildGoalCard(SavingsGoalModel goal, GoalsProvider provider) {
    final fmt     = NumberFormat('#,##0.00', 'en_US');
    final dateFmt = DateFormat('dd MMM yyyy');

    final contributed = goal.totalContributed;
    final remaining   = goal.remaining;
    final progress    = goal.progressFraction;
    final isAchieved  = contributed >= goal.goalAmount;

    final dueDate  = goal.dueDate != null ? DateTime.tryParse(goal.dueDate!) : null;
    final daysLeft = dueDate != null ? dueDate.difference(DateTime.now()).inDays : null;

    Color progressColor;
    if (isAchieved) {
      progressColor = AppTheme.success;
    } else if (progress > 0.7) {
      progressColor = AppTheme.info;
    } else if (progress > 0.4) {
      progressColor = AppTheme.warning;
    } else {
      progressColor = AppTheme.error;
    }

    return Dismissible(
      key: Key('goal_${goal.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: AppTheme.success,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline, color: Colors.white, size: 24),
            SizedBox(height: 4),
            Text('Mark Done',
                style: TextStyle(color: Colors.white, fontSize: 11)),
          ],
        ),
      ),
      confirmDismiss: (_) => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Close Goal'),
          content: Text(
              'Mark "${goal.name}" as complete and remove it from active goals?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: AppTheme.success),
              child: const Text('Mark Complete'),
            ),
          ],
        ),
      ),
      onDismissed: (_) async {
        final success = await provider.closeGoal(goal.id);
        if (!success && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to close goal.'),
              backgroundColor: AppTheme.error,
            ),
          );
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: isAchieved
              ? Border.all(color: AppTheme.success.withOpacity(0.5))
              : null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            // ── Main card content ──────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Goal name + achieved badge
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: progressColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.flag_outlined,
                            size: 20, color: progressColor),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          goal.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ),
                      if (isAchieved)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppTheme.success.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            '✓ Achieved',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.success),
                          ),
                        ),
                    ],
                  ),

                  const SizedBox(height: 14),

                  // Progress bar
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      backgroundColor: AppTheme.divider,
                      valueColor: AlwaysStoppedAnimation<Color>(progressColor),
                      minHeight: 8,
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Contributed | Still needed | Progress row
                  Row(
                    children: [
                      Expanded(
                        child: _statBox(
                          label: 'Contributed',
                          value: '${AppConstants.currency} ${fmt.format(contributed)}',
                          color: AppTheme.success,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _statBox(
                          label: 'Still Needed',
                          value: isAchieved
                              ? 'Goal Met!'
                              : '${AppConstants.currency} ${fmt.format(remaining)}',
                          color: isAchieved ? AppTheme.success : progressColor,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _statBox(
                          label: 'Progress',
                          value: '${goal.progressPercent.toStringAsFixed(1)}%',
                          color: progressColor,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),

                  // Target amount
                  Text(
                    'Target: ${AppConstants.currency} ${fmt.format(goal.goalAmount)}',
                    style: const TextStyle(
                        fontSize: 12, color: AppTheme.textSecondary),
                  ),

                  // Due date + days left
                  if (dueDate != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.calendar_today_outlined,
                            size: 13, color: AppTheme.textSecondary),
                        const SizedBox(width: 4),
                        Text(
                          'Due ${dateFmt.format(dueDate)}',
                          style: const TextStyle(
                              fontSize: 12, color: AppTheme.textSecondary),
                        ),
                        const SizedBox(width: 10),
                        if (daysLeft != null)
                          Text(
                            daysLeft > 0
                                ? '$daysLeft days left'
                                : daysLeft == 0
                                    ? 'Due today!'
                                    : 'Overdue by ${-daysLeft} days',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: daysLeft < 0
                                  ? AppTheme.error
                                  : daysLeft <= 7
                                      ? AppTheme.warning
                                      : AppTheme.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ],

                  const SizedBox(height: 6),
                  const Text(
                    'Swipe left to mark as complete',
                    style: TextStyle(
                        fontSize: 10,
                        color: AppTheme.textSecondary,
                        fontStyle: FontStyle.italic),
                  ),
                ],
              ),
            ),

            // ── Add Contribution button ────────────────────────────────────
            if (!isAchieved)
              InkWell(
                onTap: () => _showContributeSheet(goal, provider),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(14),
                  bottomRight: Radius.circular(14),
                ),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.06),
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(14),
                      bottomRight: Radius.circular(14),
                    ),
                    border: Border(
                      top: BorderSide(
                          color: AppTheme.primary.withOpacity(0.15)),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_circle_outline,
                          size: 16, color: AppTheme.primary),
                      const SizedBox(width: 6),
                      Text(
                        'Add Contribution',
                        style: TextStyle(
                          fontSize: 13,
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
      ),
    );
  }

  // ─── Contribute bottom sheet ──────────────────────────────────────────────
  void _showContributeSheet(SavingsGoalModel goal, GoalsProvider provider) {
    final amountController = TextEditingController();
    final noteController   = TextEditingController();
    final formKey          = GlobalKey<FormState>();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20, right: 20, top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.savings_outlined,
                          size: 20, color: AppTheme.primary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Add to ${goal.name}',
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 16),
                          ),
                          Text(
                            'Already saved: ${AppConstants.currency} ${NumberFormat('#,##0.00', 'en_US').format(goal.totalContributed)}',
                            style: const TextStyle(
                                fontSize: 12,
                                color: AppTheme.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // Amount field
                const Text('Amount (KES)',
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: AppTheme.textSecondary)),
                const SizedBox(height: 8),
                TextFormField(
                  controller: amountController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                        RegExp(r'^\d+\.?\d{0,2}')),
                  ],
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: '0.00',
                    prefixText: 'KES  ',
                    prefixIcon: Icon(Icons.attach_money),
                  ),
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w700),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Enter an amount.';
                    }
                    if (double.tryParse(value) == null ||
                        double.parse(value) <= 0) {
                      return 'Enter a valid amount greater than 0.';
                    }
                    return null;
                  },
                ),

                // Quick amount chips
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [500, 1000, 2000, 5000, 10000]
                      .map((amt) => ActionChip(
                            label: Text('$amt'),
                            onPressed: () =>
                                amountController.text = amt.toString(),
                            backgroundColor: AppTheme.surface,
                            labelStyle: const TextStyle(
                                fontSize: 12, color: AppTheme.primary),
                            side:
                                const BorderSide(color: AppTheme.primary),
                          ))
                      .toList(),
                ),

                const SizedBox(height: 16),

                // Note field (optional)
                const Text('Note (optional)',
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: AppTheme.textSecondary)),
                const SizedBox(height: 8),
                TextFormField(
                  controller: noteController,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    hintText:
                        'e.g. Saved from HELB, Monthly deposit...',
                    prefixIcon: Icon(Icons.note_outlined),
                  ),
                ),

                const SizedBox(height: 24),

                // Submit button
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: Consumer<GoalsProvider>(
                    builder: (context, prov, _) => ElevatedButton.icon(
                      onPressed: prov.isContributing
                          ? null
                          : () async {
                              if (!formKey.currentState!.validate()) return;
                              final success = await prov.addContribution(
                                goalId: goal.id,
                                amount: double.parse(
                                    amountController.text.trim()),
                                note: noteController.text.trim().isEmpty
                                    ? null
                                    : noteController.text.trim(),
                              );
                              if (!mounted) return;

                              // Close the bottom sheet first.
                              Navigator.pop(ctx);

                              // If contribution succeeded, re-run analysis
                              // so dashboard score + balance update immediately
                              // without needing a manual pull-to-refresh.
                              if (success) {
                                final now = DateTime.now();
                                context.read<AnalysisProvider>().analyze(
                                  month: now.month,
                                  year: now.year,
                                );
                              }

                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(success
                                      ? 'Contribution added to ${goal.name}!'
                                      : prov.errorMessage ??
                                          'Failed to add contribution.'),
                                  backgroundColor: success
                                      ? AppTheme.success
                                      : AppTheme.error,
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            },
                      icon: prov.isContributing
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white),
                            )
                          : const Icon(Icons.savings_outlined),
                      label: Text(prov.isContributing
                          ? 'Saving...'
                          : 'Add Contribution'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ─── Stat box helper ──────────────────────────────────────────────────────
  Widget _statBox({
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 10,
                  color: color,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 3),
          Text(value,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: color),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.flag_outlined,
              size: 52, color: AppTheme.textSecondary),
          const SizedBox(height: 12),
          const Text(
            'No active savings goals.',
            style: TextStyle(
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 6),
          const Text(
            'Set a goal and start contributing\ntowards it every month.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: () =>
                Navigator.pushNamed(context, AppRoutes.addGoal),
            icon: const Icon(Icons.add),
            label: const Text('Add Your First Goal'),
          ),
        ],
      ),
    );
  }
}