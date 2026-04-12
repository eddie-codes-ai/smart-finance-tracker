// lib/models/savings_goal_model.dart
// Represents a single savings goal.
// Fields match the 'savings_goals' table to_dict() in models.py.
// totalContributed is the sum of all GoalContribution records for this goal,
// computed by the backend property and included in every to_dict() response.

class SavingsGoalModel {
  final int id;
  final int userId;
  final String name;
  final double goalAmount;
  final double totalContributed; // sum of all contributions toward this goal
  final String? dueDate;
  final String dateSet;
  final bool isActive;

  SavingsGoalModel({
    required this.id,
    required this.userId,
    required this.name,
    required this.goalAmount,
    required this.totalContributed,
    this.dueDate,
    required this.dateSet,
    required this.isActive,
  });

  /// How much is still needed to reach the goal.
  double get remaining => (goalAmount - totalContributed).clamp(0, double.infinity);

  /// Progress as a value between 0.0 and 1.0 (capped at 1.0 for the bar).
  double get progressFraction => (totalContributed / goalAmount).clamp(0.0, 1.0);

  /// Progress as a percentage string e.g. "42.5%"
  double get progressPercent => (totalContributed / goalAmount * 100).clamp(0, 150);

  factory SavingsGoalModel.fromJson(Map<String, dynamic> json) {
    return SavingsGoalModel(
      id:               (json['id'] as num).toInt(),
      userId:           (json['user_id'] as num?)?.toInt() ?? 0,
      name:             json['name'] as String,
      goalAmount:       (json['goal_amount'] as num).toDouble(),
      totalContributed: (json['total_contributed'] as num? ?? 0).toDouble(),
      dueDate:          json['due_date'] as String?,
      dateSet:          json['date_set'] as String,
      isActive:         json['is_active'] as bool,
    );
  }

  Map<String, dynamic> toJson() => {
        'id':                id,
        'user_id':           userId,
        'name':              name,
        'goal_amount':       goalAmount,
        'total_contributed': totalContributed,
        'due_date':          dueDate,
        'date_set':          dateSet,
        'is_active':         isActive,
      };
}