// lib/models/income_model.dart
class IncomeModel {
  final int id;
  final int userId;
  final double amount;
  final String incomeType;
  final String description;
  final String dateAdded;

  IncomeModel({
    required this.id,
    required this.userId,
    required this.amount,
    required this.incomeType,
    required this.description,
    required this.dateAdded,
  });

  factory IncomeModel.fromJson(Map<String, dynamic> json) {
    return IncomeModel(
      id:          (json['id'] as num).toInt(),
      userId:      (json['user_id'] as num?)?.toInt() ?? 0,  // FIX: user_id not always returned by backend
      amount:      (json['amount'] as num).toDouble(),
      incomeType:  json['income_type'] as String? ?? '',
      description: json['description'] as String? ?? '',
      dateAdded:   json['date_added'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'id':          id,
    'user_id':     userId,
    'amount':      amount,
    'income_type': incomeType,
    'description': description,
    'date_added':  dateAdded,
  };
}