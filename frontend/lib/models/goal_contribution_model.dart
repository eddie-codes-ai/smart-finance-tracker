// lib/models/goal_contribution_model.dart
// Represents a single contribution made toward a savings goal.
// Fields match the 'goal_contributions' table to_dict() in models.py.
// goalName is only present when fetched from GET /api/contributions (all contributions).

class GoalContributionModel {
  final int id;
  final int goalId;
  final int userId;
  final double amount;
  final String? note;       // optional — e.g. "Saved from HELB"
  final String dateAdded;
  final String? goalName;   // only present in /api/contributions response

  GoalContributionModel({
    required this.id,
    required this.goalId,
    required this.userId,
    required this.amount,
    this.note,
    required this.dateAdded,
    this.goalName,
  });

  factory GoalContributionModel.fromJson(Map<String, dynamic> json) {
    return GoalContributionModel(
      id:         (json['id'] as num).toInt(),
      goalId:     (json['goal_id'] as num).toInt(),
      userId:     (json['user_id'] as num).toInt(),
      amount:     (json['amount'] as num).toDouble(),
      note:       json['note'] as String?,
      dateAdded:  json['date_added'] as String,
      goalName:   json['goal_name'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id':         id,
        'goal_id':    goalId,
        'user_id':    userId,
        'amount':     amount,
        'note':       note,
        'date_added': dateAdded,
        'goal_name':  goalName,
      };
}