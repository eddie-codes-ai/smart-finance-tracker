// lib/models/guardian_model.dart
// Represents the linked guardian and the latest guardian report.
// Covers both the 'guardians' and 'guardian_reports' tables in models.py.

class GuardianModel {
  final int id;
  final int userId;
  final String phoneNumber;
  final bool isActive;
  final String? lastNotified; // nullable - null if never notified
  final String createdAt;

  GuardianModel({
    required this.id,
    required this.userId,
    required this.phoneNumber,
    required this.isActive,
    this.lastNotified,
    required this.createdAt,
  });

  factory GuardianModel.fromJson(Map<String, dynamic> json) {
    return GuardianModel(
      id: json['id'],
      userId: json['user_id'],
      phoneNumber: json['phone_number'],
      isActive: json['is_active'],
      lastNotified: json['last_notified'],
      createdAt: json['created_at'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'phone_number': phoneNumber,
      'is_active': isActive,
      'last_notified': lastNotified,
      'created_at': createdAt,
    };
  }
}

// Separate model for a guardian report record from 'guardian_reports' table.
class GuardianReportModel {
  final int id;
  final int userId;
  final String reportText;
  final double score;
  final String trigger; // 'auto' | 'manual'
  final String createdAt;

  GuardianReportModel({
    required this.id,
    required this.userId,
    required this.reportText,
    required this.score,
    required this.trigger,
    required this.createdAt,
  });

  factory GuardianReportModel.fromJson(Map<String, dynamic> json) {
    return GuardianReportModel(
      id: json['id'],
      userId: json['user_id'],
      reportText: json['report_text'],
      score: (json['score'] as num).toDouble(),
      trigger: json['trigger'],
      createdAt: json['created_at'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'report_text': reportText,
      'score': score,
      'trigger': trigger,
      'created_at': createdAt,
    };
  }
}