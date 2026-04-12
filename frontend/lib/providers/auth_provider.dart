// lib/providers/auth_provider.dart
// UPDATED: Added updateProfile() method for the Profile/Account Settings screen.

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:frontend/data/local/secure_storage.dart';
import 'package:frontend/data/remote/api_client.dart';
import 'package:frontend/models/user_model.dart';

class AuthProvider extends ChangeNotifier {

  // ── Google Sign-In client ─────────────────────────────────────────────────
  // Replace YOUR_WEB_CLIENT_ID with your actual Web Client ID from Google Cloud Console
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    serverClientId: 'YOUR_WEB_CLIENT_ID.apps.googleusercontent.com',
  );

  // ── State ─────────────────────────────────────────────────────────────────
  UserModel? _user;
  bool       _isLoading = false;
  String?    _error;

  UserModel? get user      => _user;
  bool       get isLoading => _isLoading;
  String?    get error     => _error;
  bool       get isLoggedIn => _user != null;

  void _setLoading(bool val) { _isLoading = val; notifyListeners(); }
  void clearError() { _error = null; notifyListeners(); }

  // ═══════════════════════════════════════════════════════════════════════════
  // STANDARD AUTH
  // ═══════════════════════════════════════════════════════════════════════════

  /// Restore session from stored JWT token on app launch.
  Future<bool> restoreSession() async {
    return await SecureStorage.isLoggedIn();
  }

  /// Register a new account.
  /// [email] is optional but required for Forgot Password to work.
  Future<bool> register(
    String username,
    String password, {
    String? email,
  }) async {
    _setLoading(true);
    _error = null;
    try {
      final response = await ApiClient.register(username, password, email: email);
      if (response['status'] == 'success') {
        _user = UserModel.fromJson(response['user']);
        await SecureStorage.saveToken(response['token']);
        await SecureStorage.saveUsername(_user!.username);
        _setLoading(false);
        return true;
      }
      _error = response['message'] ?? 'Registration failed.';
      _setLoading(false);
      return false;
    } catch (e) {
      _error = 'Network error: $e';
      _setLoading(false);
      return false;
    }
  }

  /// Log in with username and password.
  Future<bool> login(String username, String password) async {
    _setLoading(true);
    _error = null;
    try {
      final response = await ApiClient.login(username, password);
      if (response['status'] == 'success') {
        _user = UserModel.fromJson(response['user']);
        await SecureStorage.saveToken(response['token']);
        await SecureStorage.saveUsername(_user!.username);
        _setLoading(false);
        return true;
      }
      _error = response['message'] ?? 'Login failed.';
      _setLoading(false);
      return false;
    } catch (e) {
      _error = 'Network error: $e';
      _setLoading(false);
      return false;
    }
  }

  /// Clear session and sign out.
  Future<void> logout() async {
    await SecureStorage.clearAll();
    try { await _googleSignIn.signOut(); } catch (_) {}
    _user = null;
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // GOOGLE SIGN-IN
  // ═══════════════════════════════════════════════════════════════════════════

  Future<bool> signInWithGoogle() async {
    _setLoading(true);
    _error = null;
    try {
      final account = await _googleSignIn.signIn();
      if (account == null) {
        _error = 'Google sign-in was cancelled.';
        _setLoading(false);
        return false;
      }
      final auth    = await account.authentication;
      final idToken = auth.idToken;
      if (idToken == null) {
        _error = 'Failed to get Google token. Check GOOGLE_CLIENT_ID on the server.';
        _setLoading(false);
        return false;
      }
      final response = await ApiClient.googleSignIn(idToken);
      if (response['status'] == 'success') {
        _user = UserModel.fromJson(response['user']);
        await SecureStorage.saveToken(response['token']);
        await SecureStorage.saveUsername(_user!.username);
        _setLoading(false);
        return true;
      }
      _error = response['message'] ?? 'Google sign-in failed.';
      _setLoading(false);
      return false;
    } catch (e) {
      _error = 'Google sign-in error: $e';
      _setLoading(false);
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // FORGOT PASSWORD
  // ═══════════════════════════════════════════════════════════════════════════

  Future<bool> forgotPassword(String email) async {
    _setLoading(true);
    _error = null;
    try {
      final response = await ApiClient.forgotPassword(email);
      _setLoading(false);
      if (response['status'] == 'success') return true;
      _error = response['message'] ?? 'Request failed.';
      return false;
    } catch (e) {
      _error = 'Network error: $e';
      _setLoading(false);
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // RESET PASSWORD
  // ═══════════════════════════════════════════════════════════════════════════

  Future<bool> resetPassword(String email, String code, String newPassword) async {
    _setLoading(true);
    _error = null;
    try {
      final response = await ApiClient.resetPassword(email, code, newPassword);
      _setLoading(false);
      if (response['status'] == 'success') return true;
      _error = response['message'] ?? 'Password reset failed.';
      return false;
    } catch (e) {
      _error = 'Network error: $e';
      _setLoading(false);
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // UPDATE PROFILE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Update username, email, and/or password.
  /// On success, updates the in-memory [_user] with the new values returned
  /// from the backend so the UI reflects changes immediately without re-login.
  ///
  /// [currentPassword] is required when [newPassword] is provided.
  /// Returns true on success, false on failure (error message set in [_error]).
  Future<bool> updateProfile({
    String? username,
    String? email,
    String? newPassword,
    String? currentPassword,
  }) async {
    _setLoading(true);
    _error = null;
    try {
      final response = await ApiClient.updateProfile(
        username:        username,
        email:           email,
        newPassword:     newPassword,
        currentPassword: currentPassword,
      );
      if (response['status'] == 'success') {
        // Refresh in-memory user from the updated backend response
        _user = UserModel.fromJson(response['user']);
        // Keep secure storage username in sync
        await SecureStorage.saveUsername(_user!.username);
        _setLoading(false);
        return true;
      }
      _error = response['message'] ?? 'Update failed.';
      _setLoading(false);
      return false;
    } catch (e) {
      _error = 'Network error: $e';
      _setLoading(false);
      return false;
    }
  }
}