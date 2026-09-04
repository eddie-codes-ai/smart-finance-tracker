// lib/core/app_lock.dart
//
// Biometric app lock: requires fingerprint, face or the device passcode before
// financial data is shown again after the app has been away.
//
// Deliberately a *screen* lock, not an account lock. It gates what is displayed
// on this device; the session itself is controlled by the JWT. Someone who
// picks up an unlocked phone should not be able to read the owner's spending,
// but forgetting a fingerprint must never lock anyone out of their own account
// — there is always a way past that ends in signing out rather than a dead end.

import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppLock {
  AppLock._();

  static const String _enabledKey = 'app_lock_enabled';

  /// Time the app may spend in the background before it re-locks.
  ///
  /// Without this, glancing at an M-Pesa SMS or answering a notification would
  /// demand a fingerprint on the way back, every time — which is how people end
  /// up turning the feature off.
  static const Duration graceWindow = Duration(seconds: 30);

  static final LocalAuthentication _auth = LocalAuthentication();

  /// Whether this device can authenticate at all — a biometric sensor, or a
  /// PIN/pattern/passcode it can fall back to.
  static Future<bool> isAvailable() async {
    try {
      return await _auth.isDeviceSupported();
    } catch (e) {
      debugPrint('AppLock: device support check failed: $e');
      return false;
    }
  }

  /// True when the device has an actual biometric enrolled, as opposed to only
  /// a passcode. Used for wording, so the setting does not promise a
  /// fingerprint prompt on a device that will show a PIN pad.
  static Future<bool> hasBiometrics() async {
    try {
      if (!await _auth.canCheckBiometrics) return false;
      return (await _auth.getAvailableBiometrics()).isNotEmpty;
    } catch (e) {
      debugPrint('AppLock: biometric enrolment check failed: $e');
      return false;
    }
  }

  static Future<bool> isEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_enabledKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, value);
  }

  /// Prompt for biometrics or the device passcode.
  ///
  /// Returns true when the user proved who they are. `biometricOnly: false`
  /// matters: it lets someone in with their PIN or pattern when a fingerprint
  /// fails or their sensor is wet, instead of stranding them.
  static Future<bool> authenticate({
    String reason = 'Unlock Smart Finance Tracker',
  }) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: false,   // allow PIN / pattern / passcode as a fallback
          stickyAuth: true,       // survive the app being briefly backgrounded
          useErrorDialogs: true,
        ),
      );
    } catch (e) {
      // No sensor, nothing enrolled, too many attempts, or the platform channel
      // is unavailable. Treat all of them as "not authenticated" and let the
      // caller decide - never as an error the user has to interpret.
      debugPrint('AppLock: authentication failed: $e');
      return false;
    }
  }
}
