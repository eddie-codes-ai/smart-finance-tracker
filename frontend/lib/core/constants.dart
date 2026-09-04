// lib/core/constants.dart
// Central place for all app-wide constants.
// Change baseUrl here if your backend URL changes - nowhere else.

class AppConstants {
  // ─── Backend ────────────────────────────────────────────────────────────────
  // API base URL. Overridable at build time, so switching between a local
  // backend and a deployed one never means editing this file:
  //
  //     flutter run --dart-define=API_BASE_URL=https://your-host/api
  //
  // The default assumes the backend is reachable on the device's own
  // localhost, which is true for both a USB-attached phone and an emulator
  // once you forward the port over adb:
  //
  //     cd backend && python app.py          # terminal 1
  //     adb reverse tcp:5000 tcp:5000        # terminal 2, once per connect
  //     flutter run
  //
  // adb reverse tunnels the phone's localhost:5000 to this machine over the
  // cable, so there is no LAN IP to look up, nothing for the firewall to
  // block, and no requirement to share a Wi-Fi network. Without it, use the
  // machine's LAN IP instead:
  //
  //     flutter run --dart-define=API_BASE_URL=http://192.168.1.20:5000/api
  //
  // Note that plain http only works in debug builds - see
  // android/app/src/debug/res/xml/network_security_config.xml.
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:5000/api',
  );

  // ─── Expense Categories ─────────────────────────────────────────────────────
  // Must match the category values used in the Flask backend exactly.
  static const List<String> expenseCategories = [
    'Food',
    'Transport',
    'Entertainment',
    'Shopping',
    'Health',
    'Education',
    'Utilities',
    'Rent',
    'Other',
  ];

  // ─── Income Types ───────────────────────────────────────────────────────────
  // Must match income_type enum values in the Flask backend exactly.
  static const List<String> incomeTypes = [
    'monthly',
    'daily',
    'helb',
    'parental',
    'gig',
    'other',
  ];

  // ─── Expense Types ──────────────────────────────────────────────────────────
  static const List<String> expenseTypes = [
    'daily',
    'monthly',
    'one-time',
    'recurring',
  ];

  // ─── Score Category Labels ──────────────────────────────────────────────────
  // These match the finalize() output from the Experta engine.
  static const Map<String, String> scoreCategories = {
    'Critical': 'Critical',
    'At Risk': 'At Risk',
    'Average': 'Average',
    'Good': 'Good',
    'Very Good': 'Very Good',
    'Excellent': 'Excellent',
    'Elite': 'Elite',
  };

  // ─── Secure Storage Keys ────────────────────────────────────────────────────
  // Keys used to store/retrieve values from flutter_secure_storage.
  static const String tokenKey = 'jwt_token';
  static const String refreshTokenKey = 'jwt_refresh_token';
  static const String usernameKey = 'username';

  // ─── Misc ───────────────────────────────────────────────────────────────────
  static const String appName = 'Smart Finance Tracker';
  static const String currency = 'KES';
}