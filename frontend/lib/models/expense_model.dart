// lib/models/expense_model.dart
class ExpenseModel {
  final int id;
  final int userId;
  final double amount;
  final String category;
  final String description;
  final String expenseType;
  final String? recurrenceInterval;
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
      id:                  (json['id'] as num).toInt(),
      userId:              (json['user_id'] as num?)?.toInt() ?? 0,  // FIX: user_id not always returned
      amount:              (json['amount'] as num).toDouble(),
      category:            json['category'] as String? ?? 'Other',
      description:         json['description'] as String? ?? '',
      expenseType:         json['expense_type'] as String? ?? 'daily',
      recurrenceInterval:  json['recurrence_interval'] as String?,
      dateAdded:           json['date_added'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'id':                  id,
    'user_id':             userId,
    'amount':              amount,
    'category':            category,
    'description':         description,
    'expense_type':        expenseType,
    'recurrence_interval': recurrenceInterval,
    'date_added':          dateAdded,
  };
}