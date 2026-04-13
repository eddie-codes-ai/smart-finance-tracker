// lib/providers/auth_provider.dart
// UPDATED: Added requestDeletion() and cancelDeletion() for 96-hour
// account deletion grace period. Login now stores pending_deletion
// state so the profile screen can show the cancellation banner.

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:frontend/data/local/secure_storage.dart';
import 'package:frontend/data/remote/api_client.dart';
import 'package:frontend/models/user_model.dart';

class AuthProvider extends ChangeNotifier {

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    serverClientId: '866645622012-5km05daf6mniv6f5i5e1p5tq2be3m204.apps.googleusercontent.com.',
  );

  // ── State ─────────────────────────────────────────────────────────────────
  UserModel? _user;
  bool       _isLoading      = false;
  String?    _error;
  bool       _pendingDeletion = false;   // true if account is scheduled for deletion
  String?    _deletionDueAt;             // ISO string of when deletion will execute

  UserModel? get user             => _user;
  bool       get isLoading        => _isLoading;
  String?    get error            => _error;
  bool       get isLoggedIn       => _user != null;
  bool       get pendingDeletion  => _pendingDeletion;
  String?    get deletionDueAt    => _deletionDueAt;

  void _setLoading(bool val) { _isLoading = val; notifyListeners(); }
  void clearError() { _error = null; notifyListeners(); }

  // ═══════════════════════════════════════════════════════════════════════════
  // STANDARD AUTH
  // ═══════════════════════════════════════════════════════════════════════════

  Future<bool> restoreSession() async {
    return await SecureStorage.isLoggedIn();
  }

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

  Future<bool> login(String username, String password) async {
    _setLoading(true);
    _error = null;
    try {
      final response = await ApiClient.login(username, password);
      if (response['status'] == 'success') {
        _user = UserModel.fromJson(response['user']);
        await SecureStorage.saveToken(response['token']);
        await SecureStorage.saveUsername(_user!.username);

        // Store pending deletion state so the profile screen can show
        // the cancellation banner immediately after login.
        _pendingDeletion = response['pending_deletion'] ?? false;
        _deletionDueAt   = response['deletion_due_at'] as String?;

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

  Future<void> logout() async {
    await SecureStorage.clearAll();
    try { await _googleSignIn.signOut(); } catch (_) {}
    _user            = null;
    _pendingDeletion = false;
    _deletionDueAt   = null;
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
  // FORGOT / RESET PASSWORD
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
        _user = UserModel.fromJson(response['user']);
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

  // ═══════════════════════════════════════════════════════════════════════════
  // ACCOUNT DELETION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Request account deletion. Password required for confirmation.
  /// On success, sets pendingDeletion = true and stores deletionDueAt.
  /// The account will be permanently deleted after 96 hours unless cancelled.
  Future<bool> requestDeletion({required String password}) async {
    _setLoading(true);
    _error = null;
    try {
      final response = await ApiClient.deleteAccount(password: password);
      if (response['status'] == 'success') {
        _pendingDeletion = true;
        _deletionDueAt   = response['deletion_due_at'] as String?;
        _setLoading(false);
        return true;
      }
      _error = response['message'] ?? 'Failed to schedule deletion.';
      _setLoading(false);
      return false;
    } catch (e) {
      _error = 'Network error: $e';
      _setLoading(false);
      return false;
    }
  }

  /// Cancel a pending account deletion request.
  /// On success, clears pendingDeletion and deletionDueAt.
  Future<bool> cancelDeletion() async {
    _setLoading(true);
    _error = null;
    try {
      final response = await ApiClient.cancelDeletion();
      if (response['status'] == 'success') {
        _pendingDeletion = false;
        _deletionDueAt   = null;
        // Refresh user from response so to_dict fields are up to date
        if (response['user'] != null) {
          _user = UserModel.fromJson(response['user']);
        }
        _setLoading(false);
        return true;
      }
      _error = response['message'] ?? 'Failed to cancel deletion.';
      _setLoading(false);
      return false;
    } catch (e) {
      _error = 'Network error: $e';
      _setLoading(false);
      return false;
    }
  }
}