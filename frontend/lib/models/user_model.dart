// lib/models/user_model.dart
// Represents the authenticated user.
// Fields match the 'users' table to_dict() in models.py.

class UserModel {
  final int id;
  final String username;
  final String createdAt;

  UserModel({
    required this.id,
    required this.username,
    required this.createdAt,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'],
      username: json['username'],
      createdAt: json['created_at'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'created_at': createdAt,
    };
  }
}