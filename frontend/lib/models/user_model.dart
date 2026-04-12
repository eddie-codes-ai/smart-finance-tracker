// lib/models/user_model.dart
class UserModel {
  final int id;
  final String username;
  final String? email;      // optional — added for Google Sign-In and password reset
  final String createdAt;

  UserModel({
    required this.id,
    required this.username,
    this.email,
    required this.createdAt,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id:        (json['id'] as num).toInt(),
      username:  json['username'] as String? ?? '',
      email:     json['email'] as String?,
      createdAt: json['created_at'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'id':         id,
    'username':   username,
    'email':      email,
    'created_at': createdAt,
  };
}