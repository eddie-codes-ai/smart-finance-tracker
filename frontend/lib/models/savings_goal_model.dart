// lib/models/savings_goal_model.dart
// Represents a single savings goal.
// Fields match the 'savings_goals' table to_dict() in models.py.

class SavingsGoalModel {
  final int id;
  final int userId;
  final String name;
  final double goalAmount;
  final String? dueDate;  // nullable - student may not set a deadline
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
      id: json['id'],
      userId: json['user_id'],
      name: json['name'],
      goalAmount: (json['goal_amount'] as num).toDouble(),
      dueDate: json['due_date'],
      dateSet: json['date_set'],
      isActive: json['is_active'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'name': name,
      'goal_amount': goalAmount,
      'due_date': dueDate,
      'date_set': dateSet,
      'is_active': isActive,
    };
  }
}