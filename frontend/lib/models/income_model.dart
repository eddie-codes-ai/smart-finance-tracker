// lib/models/income_model.dart
// Represents a single income record.
// Fields match the 'incomes' table to_dict() in models.py.

class IncomeModel {
  final int id;
  final int userId;
  final double amount;
  final String incomeType; // monthly | daily | helb | parental | gig | other
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
      id: json['id'],
      userId: json['user_id'],
      // amount comes as int or double from SQLite - always cast to double
      amount: (json['amount'] as num).toDouble(),
      incomeType: json['income_type'],
      description: json['description'] ?? '',
      dateAdded: json['date_added'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'amount': amount,
      'income_type': incomeType,
      'description': description,
      'date_added': dateAdded,
    };
  }
}