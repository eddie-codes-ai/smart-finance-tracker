// lib/providers/auth_provider.dart
// UPDATED: Added requestDeletion() and cancelDeletion() for 96-hour
// account deletion grace period. Login now stores pending_deletion
// state so the profile screen can show the cancellation banner.

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:frontend/core/device_timezone.dart';
import 'package:frontend/data/local/secure_storage.dart';
import 'package:frontend/data/remote/api_client.dart';
import 'package:frontend/models/user_model.dart';

class AuthProvider extends ChangeNotifier {

  // Must match android/app/src/main/res/values/strings.xml exactly, and the
  // GOOGLE_CLIENT_ID the server verifies against. This carried a trailing dot
  // that the other two do not, which made the audience check fail.
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    serverClientId: '866645622012-5km05daf6mniv6f5i5e1p5tq2be3m204.apps.googleusercontent.com',
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

  /// Persist the tokens from a sign-in, registration or password change.
  ///
  /// The refresh token is what keeps the session alive across the access
  /// token's hourly expiry, so losing it silently would sign the user out an
  /// hour later for no visible reason.
  Future<void> _storeSession(Map<String, dynamic> response) async {
    final token = response['token'] as String?;
    if (token != null && token.isNotEmpty) {
      await SecureStorage.saveToken(token);
    }
    final refresh = response['refresh_token'] as String?;
    if (refresh != null && refresh.isNotEmpty) {
      await SecureStorage.saveRefreshToken(refresh);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STANDARD AUTH
  // ═══════════════════════════════════════════════════════════════════════════

  /// Restore a session on app start.
  ///
  /// This used to return whether a token *string* existed in storage, without
  /// asking the server whether it was still valid and without reloading the
  /// user - which is why the profile screen showed "Unknown" with no email
  /// until the next manual sign-in. Now that tokens expire, believing storage
  /// would route the user into a dashboard where every request fails.
  Future<bool> restoreSession() async {
    if (!await SecureStorage.isLoggedIn()) return false;
    try {
      final response = await ApiClient.me();
      if (response['status'] != 'success') return false;
      _user            = UserModel.fromJson(response['user']);
      _pendingDeletion = response['pending_deletion'] ?? false;
      _deletionDueAt   = response['deletion_due_at'] as String?;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      // An expired or revoked session is a clean "no". A network failure is
      // not proof the session ended, but there is no way to use the app
      // offline either, so both send the user to the sign-in screen.
      if (e.isAuthFailure) await SecureStorage.clearAll();
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> register(
    String username,
    String password, {
    String? email,
  }) async {
    _setLoading(true);
    _error = null;
    try {
      // Seed the home zone from the device at sign-up. It is only ever seeded
      // here: re-reading it on every login would re-pin the zone each time the
      // user travelled, which is exactly what a *home* zone must not do.
      final response = await ApiClient.register(
        username, password,
        email: email,
        timezone: await DeviceTimezone.current(),
      );
      if (response['status'] == 'success') {
        _user = UserModel.fromJson(response['user']);
        await _storeSession(response);
        await SecureStorage.saveUsername(_user!.username);
        _setLoading(false);
        return true;
      }
      _error = response['message'] ?? 'Registration failed.';
      _setLoading(false);
      return false;
    } on ApiException catch (e) {
      _error = e.message;
      _setLoading(false);
      return false;
    } catch (e) {
      _error = 'Something went wrong. Please try again.';
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
        await _storeSession(response);
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
    } on ApiException catch (e) {
      _error = e.message;
      _setLoading(false);
      return false;
    } catch (e) {
      _error = 'Something went wrong. Please try again.';
      _setLoading(false);
      return false;
    }
  }

  Future<void> logout() async {
    // Tell the server first, so tokens already copied elsewhere stop working.
    // Clearing only this device left a stolen token valid indefinitely.
    // Best-effort: a failure here must not trap the user in a signed-in state.
    try { await ApiClient.logout(); } catch (_) {}
    await SecureStorage.clearAll();
    try { await _googleSignIn.signOut(); } catch (_) {}
    clearSession();
  }

  /// Drop local session state without calling the server.
  ///
  /// Used when the session has already ended server-side - an expired or
  /// revoked refresh token - where calling logout would only fail.
  void clearSession() {
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
        await _storeSession(response);
        await SecureStorage.saveUsername(_user!.username);
        _setLoading(false);
        return true;
      }
      _error = response['message'] ?? 'Google sign-in failed.';
      _setLoading(false);
      return false;
    } on ApiException catch (e) {
      _error = e.message;
      _setLoading(false);
      return false;
    } catch (e) {
      _error = 'Google sign-in failed. Please try again.';
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
    } on ApiException catch (e) {
      _error = e.message;
      _setLoading(false);
      return false;
    } catch (e) {
      _error = 'Something went wrong. Please try again.';
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
    } on ApiException catch (e) {
      _error = e.message;
      _setLoading(false);
      return false;
    } catch (e) {
      _error = 'Something went wrong. Please try again.';
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
    String? timezone,
  }) async {
    _setLoading(true);
    _error = null;
    try {
      final response = await ApiClient.updateProfile(
        username:        username,
        email:           email,
        newPassword:     newPassword,
        currentPassword: currentPassword,
        timezone:        timezone,
      );
      if (response['status'] == 'success') {
        _user = UserModel.fromJson(response['user']);
        // A password change revokes every session, so the server issues this
        // device a replacement pair. Without storing it the user would be
        // signed out of the app they just changed their password in.
        await _storeSession(response);
        await SecureStorage.saveUsername(_user!.username);
        _setLoading(false);
        return true;
      }
      _error = response['message'] ?? 'Update failed.';
      _setLoading(false);
      return false;
    } on ApiException catch (e) {
      _error = e.message;
      _setLoading(false);
      return false;
    } catch (e) {
      _error = 'Something went wrong. Please try again.';
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
    } on ApiException catch (e) {
      _error = e.message;
      _setLoading(false);
      return false;
    } catch (e) {
      _error = 'Something went wrong. Please try again.';
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
    } on ApiException catch (e) {
      _error = e.message;
      _setLoading(false);
      return false;
    } catch (e) {
      _error = 'Something went wrong. Please try again.';
      _setLoading(false);
      return false;
    }
  }
}