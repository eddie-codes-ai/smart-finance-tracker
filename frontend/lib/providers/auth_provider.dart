// lib/providers/auth_provider.dart
// Manages authentication state for the entire app.
// Handles register, login, logout and token persistence.

import 'package:flutter/material.dart';
import '../data/local/secure_storage.dart';
import '../data/remote/api_client.dart';
import '../models/user_model.dart';

class AuthProvider extends ChangeNotifier {
  UserModel? _user;
  bool _isLoading = false;
  String? _errorMessage;

  // ─── Getters ─────────────────────────────────────────────────────────────────
  UserModel? get user => _user;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isLoggedIn => _user != null;

  // ─── Register ────────────────────────────────────────────────────────────────
  /// Returns true on success, false on failure.
  /// On success saves token + username to secure storage.
  Future<bool> register({
    required String username,
    required String password,
  }) async {
    _setLoading(true);
    try {
      final data = await ApiClient.register(
        username: username,
        password: password,
      );
      _user = UserModel.fromJson(data['user']);
      await SecureStorage.saveToken(data['token']);
      await SecureStorage.saveUsername(_user!.username);
      _errorMessage = null;
      return true;
    } on ApiException catch (e) {
      _errorMessage = e.message;
      return false;
    } catch (e) {
      _errorMessage = 'Network error. Is the backend running?';
      return false;
    } finally {
      _setLoading(false);
    }
  }

  // ─── Login ───────────────────────────────────────────────────────────────────
  /// Returns true on success, false on failure.
  Future<bool> login({
    required String username,
    required String password,
  }) async {
    _setLoading(true);
    try {
      final data = await ApiClient.login(
        username: username,
        password: password,
      );
      _user = UserModel.fromJson(data['user']);
      await SecureStorage.saveToken(data['token']);
      await SecureStorage.saveUsername(_user!.username);
      _errorMessage = null;
      return true;
    } on ApiException catch (e) {
      _errorMessage = e.message;
      return false;
    } catch (e) {
      _errorMessage = 'Network error. Is the backend running?';
      return false;
    } finally {
      _setLoading(false);
    }
  }

  // ─── Restore Session ─────────────────────────────────────────────────────────
  /// Called by SplashScreen to restore user session from secure storage.
  /// If a token exists, rebuild the user object from stored username.
  Future<bool> restoreSession() async {
    final loggedIn = await SecureStorage.isLoggedIn();
    if (!loggedIn) return false;

    final username = await SecureStorage.getUsername();
    if (username == null) return false;

    // Reconstruct a minimal user object from local storage.
    // Full user data is fetched per-screen as needed.
    _user = UserModel(id: 0, username: username, createdAt: '');
    notifyListeners();
    return true;
  }

  // ─── Logout ──────────────────────────────────────────────────────────────────
  Future<void> logout() async {
    await SecureStorage.clearAll();
    _user = null;
    _errorMessage = null;
    notifyListeners();
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────────
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }
}