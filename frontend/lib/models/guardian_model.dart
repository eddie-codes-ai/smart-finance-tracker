// lib/models/guardian_model.dart
// Two model classes: GuardianModel and GuardianReportModel.
//
// FIX: All numeric fields now parsed via (json['field'] as num).toInt()
// instead of direct `as int` cast. Dart's json.decode() returns JSON numbers
// as int OR double depending on the platform, so the direct cast fails
// at runtime when the server sends e.g. score: 72.0 instead of 72.
// Using (as num).toInt() handles both cases safely.

class GuardianModel {
  final int id;
  final int userId;
  final String phoneNumber;
  final bool isActive;
  final String? lastNotified; // null if guardian has never been notified
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
      id:           (json['id'] as num).toInt(),
      userId:       (json['user_id'] as num?)?.toInt() ?? 0,
      phoneNumber:  json['phone_number'] as String,
      isActive:     json['is_active'] as bool,
      lastNotified: json['last_notified'] as String?,
      createdAt:    json['created_at'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
        'id':            id,
        'user_id':       userId,
        'phone_number':  phoneNumber,
        'is_active':     isActive,
        'last_notified': lastNotified,
        'created_at':    createdAt,
      };
}

class GuardianReportModel {
  final int id;
  final int userId;
  final String reportText;
  final int score;      // stored as int 0-100; safe-parsed via (num).toInt()
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
      id:          (json['id'] as num).toInt(),
      userId:      (json['user_id'] as num?)?.toInt() ?? 0,
      reportText:  json['report_text'] as String,
      score:       (json['score'] as num).toInt(), // THE FIX
      trigger:     json['trigger'] as String,
      createdAt:   json['created_at'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
        'id':          id,
        'user_id':     userId,
        'report_text': reportText,
        'score':       score,
        'trigger':     trigger,
        'created_at':  createdAt,
      };
}