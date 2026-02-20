// lib/ui/goals/goals_screen.dart
// Lists all active savings goals with progress toward each.
// Supports swipe-to-close (soft delete) and FAB to add a new goal.
// Progress is computed from AnalysisProvider savings vs goal_amount.

import 'package:flutter/material.dart';
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
    final analysis = context.watch<AnalysisProvider>();
    final currentSavings = analysis.result?.savings ?? 0.0;

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
                      final goal = goals.goals[index];
                      return _buildGoalCard(
                          goal, currentSavings, goals);
                    },
                  ),
      ),
    );
  }

  Widget _buildGoalCard(
    SavingsGoalModel goal,
    double currentSavings,
    GoalsProvider provider,
  ) {
    final fmt = NumberFormat('#,##0.00', 'en_US');
    final dateFmt = DateFormat('dd MMM yyyy');

    // Progress toward this goal from current month savings.
    final progress =
        (currentSavings / goal.goalAmount).clamp(0.0, 1.5);
    final progressPercent = (progress * 100).clamp(0, 150);
    final isAchieved = currentSavings >= goal.goalAmount;

    // Days remaining until due date.
    final dueDate = goal.dueDate != null
        ? DateTime.tryParse(goal.dueDate!)
        : null;
    final daysLeft = dueDate != null
        ? dueDate.difference(DateTime.now()).inDays
        : null;

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
          color: AppTheme.error,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline,
                color: Colors.white, size: 24),
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
              style:
                  TextButton.styleFrom(foregroundColor: AppTheme.success),
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
        padding: const EdgeInsets.all(16),
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
                value: progress.clamp(0.0, 1.0),
                backgroundColor: AppTheme.divider,
                valueColor:
                    AlwaysStoppedAnimation<Color>(progressColor),
                minHeight: 8,
              ),
            ),

            const SizedBox(height: 8),

            // Stats row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${AppConstants.currency} ${fmt.format(currentSavings)} of ${fmt.format(goal.goalAmount)}',
                  style: const TextStyle(
                      fontSize: 12, color: AppTheme.textSecondary),
                ),
                Text(
                  '${progressPercent.toStringAsFixed(1)}%',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: progressColor,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            // Due date + days left
            if (dueDate != null)
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
            'Set a goal and track your progress\ntowards it every month.',
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