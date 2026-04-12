// lib/models/savings_goal_model.dart
class SavingsGoalModel {
  final int id;
  final int userId;
  final String name;
  final double goalAmount;
  final String? dueDate;
  final String dateSet;
  final bool isActive;

  SavingsGoalModel({
    required this.id,
    required this.userId,
    required this.name,
    required this.goalAmount,
    this.dueDate,
    required this.dateSet,
    required this.isActive,
  });

  factory SavingsGoalModel.fromJson(Map<String, dynamic> json) {
    return SavingsGoalModel(
      id:         (json['id'] as num).toInt(),
      userId:     (json['user_id'] as num?)?.toInt() ?? 0,  // FIX: not always in response
      name:       json['name'] as String? ?? '',
      goalAmount: (json['goal_amount'] as num).toDouble(),
      dueDate:    json['due_date'] as String?,
      dateSet:    json['date_set'] as String? ?? '',
      isActive:   json['is_active'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
    'id':          id,
    'user_id':     userId,
    'name':        name,
    'goal_amount': goalAmount,
    'due_date':    dueDate,
    'date_set':    dateSet,
    'is_active':   isActive,
  };
}