// lib/data/local/secure_storage.dart
// Wraps flutter_secure_storage for all secure key-value operations.
// Used exclusively for storing and retrieving the JWT token and username.
// The device's encrypted keystore ensures token survives app restarts.

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../core/constants.dart';

class SecureStorage {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true, // uses EncryptedSharedPreferences on Android
    ),
  );

  // ─── Token ──────────────────────────────────────────────────────────────────

  /// Save JWT token after login or register.
  static Future<void> saveToken(String token) async {
    await _storage.write(key: AppConstants.tokenKey, value: token);
  }

  /// Retrieve stored JWT token. Returns null if not logged in.
  static Future<String?> getToken() async {
    return await _storage.read(key: AppConstants.tokenKey);
  }

  /// Delete token on logout.
  static Future<void> deleteToken() async {
    await _storage.delete(key: AppConstants.tokenKey);
  }

  // ─── Username ────────────────────────────────────────────────────────────────

  /// Save username alongside token so screens can display it without an API call.
  static Future<void> saveUsername(String username) async {
    await _storage.write(key: AppConstants.usernameKey, value: username);
  }

  /// Retrieve stored username.
  static Future<String?> getUsername() async {
    return await _storage.read(key: AppConstants.usernameKey);
  }

  // ─── Session ─────────────────────────────────────────────────────────────────

  /// Check if a token exists - used by SplashScreen to decide where to navigate.
  static Future<bool> isLoggedIn() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  /// Clear all stored values on logout.
  static Future<void> clearAll() async {
    await _storage.deleteAll();
  }
}