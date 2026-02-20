// lib/models/expense_model.dart
// Represents a single expense record.
// Fields match the 'expenses' table to_dict() in models.py.

class ExpenseModel {
  final int id;
  final int userId;
  final double amount;
  final String category;   // Food | Transport | Entertainment | Shopping |
                           // Health | Education | Utilities | Rent | Other
  final String description;
  final String expenseType; // daily | monthly | one-time | recurring
  final String? recurrenceInterval; // nullable - only set for recurring expenses
  final String dateAdded;

  ExpenseModel({
    required this.id,
    required this.userId,
    required this.amount,
    required this.category,
    required this.description,
    required this.expenseType,
    this.recurrenceInterval,
    required this.dateAdded,
  });

  factory ExpenseModel.fromJson(Map<String, dynamic> json) {
    return ExpenseModel(
      id: json['id'],
      userId: json['user_id'],
      amount: (json['amount'] as num).toDouble(),
      category: json['category'],
      description: json['description'] ?? '',
      expenseType: json['expense_type'],
      recurrenceInterval: json['recurrence_interval'],
      dateAdded: json['date_added'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'amount': amount,
      'category': category,
      'description': description,
      'expense_type': expenseType,
      'recurrence_interval': recurrenceInterval,
      'date_added': dateAdded,
    };
  }
}