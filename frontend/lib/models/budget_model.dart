// lib/models/budget_model.dart
class BudgetModel {
  final int id;
  final int userId;
  final String category;
  final double limit;
  final String monthYear;
  final String createdAt;

  BudgetModel({
    required this.id,
    required this.userId,
    required this.category,
    required this.limit,
    required this.monthYear,
    required this.createdAt,
  });

  factory BudgetModel.fromJson(Map<String, dynamic> json) {
    return BudgetModel(
      id:         (json['id'] as num).toInt(),
      userId:     (json['user_id'] as num?)?.toInt() ?? 0,     // FIX: not in response
      category:   json['category'] as String? ?? '',
      limit:      (json['limit'] as num).toDouble(),
      monthYear:  json['month_year'] as String? ?? '',
      createdAt:  json['created_at'] as String? ?? '',          // FIX: not in response
    );
  }

  Map<String, dynamic> toJson() => {
    'id':         id,
    'user_id':    userId,
    'category':   category,
    'limit':      limit,
    'month_year': monthYear,
    'created_at': createdAt,
  };
}