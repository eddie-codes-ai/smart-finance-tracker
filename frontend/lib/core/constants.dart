// lib/core/constants.dart
// Central place for all app-wide constants.
// Change baseUrl here if your backend URL changes - nowhere else.

class AppConstants {
  // ─── Backend ────────────────────────────────────────────────────────────────
  // ── API Base URL ──────────────────────────────────────
  // Use this for emulator testing:
 //static const String baseUrl = 'http://10.0.2.2:5000/api';

// Use this for production APK:
static const String baseUrl = 'https://smart-finance-tracker-production.up.railway.app/api';

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
  static const String usernameKey = 'username';

  // ─── Misc ───────────────────────────────────────────────────────────────────
  static const String appName = 'Smart Finance Tracker';
  static const String currency = 'KES';
}