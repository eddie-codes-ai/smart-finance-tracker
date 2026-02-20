// lib/models/budget_model.dart
// Represents a budget limit for one category in one month.
// Fields match the 'budgets' table to_dict() in models.py.

class BudgetModel {
  final int id;
  final int userId;
  final String category;
  final double limit;
  final String monthYear; // Format: YYYY-MM e.g. "2025-07"
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
      id: json['id'],
      userId: json['user_id'],
      category: json['category'],
      limit: (json['limit'] as num).toDouble(),
      monthYear: json['month_year'],
      createdAt: json['created_at'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'category': category,
      'limit': limit,
      'month_year': monthYear,
      'created_at': createdAt,
    };
  }
}