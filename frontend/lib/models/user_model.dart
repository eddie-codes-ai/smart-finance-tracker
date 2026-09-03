// lib/models/user_model.dart
// Represents the authenticated user.
// Fields match the 'users' table to_dict() in models.py.
// UPDATED: Added nullable email field — added in the password recovery session.

class UserModel {
  final int id;
  final String username;
  final String? email;     // nullable — user may not have set an email yet

  /// The user's HOME IANA zone, e.g. "Africa/Nairobi". Months and daily
  /// spending are grouped by this on the server, not by the device's current
  /// zone, so travelling doesn't re-bucket existing history.
  final String timezone;

  final String createdAt;

  UserModel({
    required this.id,
    required this.username,
    this.email,
    this.timezone = 'Africa/Nairobi',
    required this.createdAt,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id:        (json['id'] as num).toInt(),
      username:  json['username'] as String,
      email:     json['email'] as String?,
      timezone:  json['timezone'] as String? ?? 'Africa/Nairobi',
      createdAt: json['created_at'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id':         id,
      'username':   username,
      'email':      email,
      'timezone':   timezone,
      'created_at': createdAt,
    };
  }

  /// Returns a copy of this model with updated fields.
  /// Used by AuthProvider after a successful profile update.
  UserModel copyWith({
    String? username,
    String? email,
    String? timezone,
  }) {
    return UserModel(
      id:        id,
      username:  username ?? this.username,
      email:     email ?? this.email,
      timezone:  timezone ?? this.timezone,
      createdAt: createdAt,
    );
  }
}