// lib/models/user_category_model.dart
// Represents a single category available to the user.
// Default categories have is_custom: false and no id.
// Custom categories have is_custom: true and an id from the backend.

class UserCategoryModel {
  final int?   id;        // null for default categories
  final String name;
  final bool   isCustom; // false = default, true = user-added

  UserCategoryModel({
    this.id,
    required this.name,
    required this.isCustom,
  });

  factory UserCategoryModel.fromJson(Map<String, dynamic> json) {
    return UserCategoryModel(
      id:       json['id'] != null ? (json['id'] as num).toInt() : null,
      name:     json['name'] as String,
      isCustom: json['is_custom'] as bool? ?? false,
    );
  }

  /// Convenience constructor for the hardcoded default categories
  /// used as a fallback when the API is not available.
  factory UserCategoryModel.defaultCategory(String name) {
    return UserCategoryModel(id: null, name: name, isCustom: false);
  }

  Map<String, dynamic> toJson() => {
        'id':        id,
        'name':      name,
        'is_custom': isCustom,
      };
}