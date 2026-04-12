// lib/data/remote/api_client.dart
// All methods are STATIC — providers call them as ApiClient.methodName()
// ApiException is defined here for use in providers.
// UPDATED: Added updateProfile() for PUT /api/auth/profile

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:frontend/data/local/secure_storage.dart';
import 'package:frontend/core/constants.dart';

// ─── Custom exception used by providers ───────────────────────────────────────
class ApiException implements Exception {
  final String message;
  final int? statusCode;
  ApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

class ApiClient {

  static Future<Map<String, String>> _authHeaders() async {
    final token = await SecureStorage.getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // AUTH
  // ═══════════════════════════════════════════════════════════════════════════

  static Future<Map<String, dynamic>> register(
    String username,
    String password, {
    String? email,
  }) async {
    final body = <String, dynamic>{'username': username, 'password': password};
    if (email != null && email.isNotEmpty) body['email'] = email;
    final response = await http.post(
      Uri.parse('${AppConstants.baseUrl}/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> login(String username, String password) async {
    final response = await http.post(
      Uri.parse('${AppConstants.baseUrl}/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> googleSignIn(String idToken) async {
    final response = await http.post(
      Uri.parse('${AppConstants.baseUrl}/auth/google'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'id_token': idToken}),
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> forgotPassword(String email) async {
    final response = await http.post(
      Uri.parse('${AppConstants.baseUrl}/auth/forgot-password'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email}),
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> resetPassword(
    String email, String code, String newPassword,
  ) async {
    final response = await http.post(
      Uri.parse('${AppConstants.baseUrl}/auth/reset-password'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'code': code, 'new_password': newPassword}),
    );
    return jsonDecode(response.body);
  }

  /// Update profile fields. All parameters are optional.
  /// Supply only the fields the user wants to change.
  /// [currentPassword] is required when [newPassword] is provided.
  static Future<Map<String, dynamic>> updateProfile({
    String? username,
    String? email,
    String? newPassword,
    String? currentPassword,
  }) async {
    final body = <String, dynamic>{};
    if (username        != null && username.isNotEmpty)        body['username']         = username;
    if (email           != null && email.isNotEmpty)           body['email']            = email;
    if (newPassword     != null && newPassword.isNotEmpty)     body['new_password']     = newPassword;
    if (currentPassword != null && currentPassword.isNotEmpty) body['current_password'] = currentPassword;

    final response = await http.put(
      Uri.parse('${AppConstants.baseUrl}/auth/profile'),
      headers: await _authHeaders(),
      body: jsonEncode(body),
    );
    return jsonDecode(response.body);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // INCOME
  // ═══════════════════════════════════════════════════════════════════════════

  static Future<Map<String, dynamic>> addIncome({
    required double amount,
    required String incomeType,
    String description = '',
  }) async {
    final response = await http.post(
      Uri.parse('${AppConstants.baseUrl}/income'),
      headers: await _authHeaders(),
      body: jsonEncode({'amount': amount, 'income_type': incomeType, 'description': description}),
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> getIncome({int? month, int? year}) async {
    final now = DateTime.now();
    final uri = Uri.parse('${AppConstants.baseUrl}/income').replace(queryParameters: {
      'month': (month ?? now.month).toString(),
      'year':  (year  ?? now.year).toString(),
    });
    final response = await http.get(uri, headers: await _authHeaders());
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> deleteIncome(int id) async {
    final response = await http.delete(
      Uri.parse('${AppConstants.baseUrl}/income/$id'),
      headers: await _authHeaders(),
    );
    return jsonDecode(response.body);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // EXPENSES
  // ═══════════════════════════════════════════════════════════════════════════

  static Future<Map<String, dynamic>> addExpense({
    required double amount,
    required String category,
    String description = '',
    String expenseType = 'daily',
    String? recurrenceInterval,
  }) async {
    final response = await http.post(
      Uri.parse('${AppConstants.baseUrl}/expenses'),
      headers: await _authHeaders(),
      body: jsonEncode({
        'amount': amount, 'category': category, 'description': description,
        'expense_type': expenseType, 'recurrence_interval': recurrenceInterval,
      }),
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> getExpenses({int? month, int? year}) async {
    final now = DateTime.now();
    final uri = Uri.parse('${AppConstants.baseUrl}/expenses').replace(queryParameters: {
      'month': (month ?? now.month).toString(),
      'year':  (year  ?? now.year).toString(),
    });
    final response = await http.get(uri, headers: await _authHeaders());
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> deleteExpense(int id) async {
    final response = await http.delete(
      Uri.parse('${AppConstants.baseUrl}/expenses/$id'),
      headers: await _authHeaders(),
    );
    return jsonDecode(response.body);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUDGETS
  // ═══════════════════════════════════════════════════════════════════════════

  static Future<Map<String, dynamic>> setBudget({
    required String category,
    required double limit,
    String? monthYear,
  }) async {
    final now = DateTime.now();
    final my  = monthYear ?? '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final response = await http.post(
      Uri.parse('${AppConstants.baseUrl}/budgets'),
      headers: await _authHeaders(),
      body: jsonEncode({'category': category, 'limit': limit, 'month_year': my}),
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> getBudgets({String? monthYear}) async {
    final now = DateTime.now();
    final my  = monthYear ?? '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final uri = Uri.parse('${AppConstants.baseUrl}/budgets')
        .replace(queryParameters: {'month_year': my});
    final response = await http.get(uri, headers: await _authHeaders());
    return jsonDecode(response.body);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SAVINGS GOALS
  // ═══════════════════════════════════════════════════════════════════════════

  static Future<Map<String, dynamic>> addGoal({
    required String name,
    required double goalAmount,
    required String dueDate,
  }) async {
    final response = await http.post(
      Uri.parse('${AppConstants.baseUrl}/goals'),
      headers: await _authHeaders(),
      body: jsonEncode({'name': name, 'goal_amount': goalAmount, 'due_date': dueDate}),
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> getGoals() async {
    final response = await http.get(
      Uri.parse('${AppConstants.baseUrl}/goals'),
      headers: await _authHeaders(),
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> closeGoal(int id) async {
    final response = await http.delete(
      Uri.parse('${AppConstants.baseUrl}/goals/$id'),
      headers: await _authHeaders(),
    );
    return jsonDecode(response.body);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ANALYSIS
  // ═══════════════════════════════════════════════════════════════════════════

  static Future<Map<String, dynamic>> analyze({int? month, int? year}) async {
    final now = DateTime.now();
    final response = await http.post(
      Uri.parse('${AppConstants.baseUrl}/analyze'),
      headers: await _authHeaders(),
      body: jsonEncode({'month': month ?? now.month, 'year': year ?? now.year}),
    );
    return jsonDecode(response.body);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // GUARDIAN
  // ═══════════════════════════════════════════════════════════════════════════

  static Future<Map<String, dynamic>> linkGuardian({required String phoneNumber}) async {
    final response = await http.post(
      Uri.parse('${AppConstants.baseUrl}/guardian/link'),
      headers: await _authHeaders(),
      body: jsonEncode({'phone_number': phoneNumber}),
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> getGuardianStatus() async {
    final response = await http.get(
      Uri.parse('${AppConstants.baseUrl}/guardian/status'),
      headers: await _authHeaders(),
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> unlinkGuardian() async {
    final response = await http.delete(
      Uri.parse('${AppConstants.baseUrl}/guardian/unlink'),
      headers: await _authHeaders(),
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> notifyGuardian({int? month, int? year}) async {
    final now = DateTime.now();
    final response = await http.post(
      Uri.parse('${AppConstants.baseUrl}/guardian/notify'),
      headers: await _authHeaders(),
      body: jsonEncode({'month': month ?? now.month, 'year': year ?? now.year}),
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> getGuardianReport() async {
    final response = await http.get(
      Uri.parse('${AppConstants.baseUrl}/guardian/report'),
      headers: await _authHeaders(),
    );
    return jsonDecode(response.body);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELB PLANNER
  // ═══════════════════════════════════════════════════════════════════════════

  static Future<Map<String, dynamic>> getHelbPlan() async {
    final response = await http.get(
      Uri.parse('${AppConstants.baseUrl}/helb/plan'),
      headers: await _authHeaders(),
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> saveHelbPlan({
    required String semesterName,
    required double helbAmount,
    required String startDate,
    required String endDate,
    required Map<String, double> allocations,
  }) async {
    final response = await http.post(
      Uri.parse('${AppConstants.baseUrl}/helb/plan'),
      headers: await _authHeaders(),
      body: jsonEncode({
        'semester_name': semesterName,
        'helb_amount':   helbAmount,
        'start_date':    startDate,
        'end_date':      endDate,
        'allocations':   allocations,
      }),
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> deleteHelbPlan() async {
    final response = await http.delete(
      Uri.parse('${AppConstants.baseUrl}/helb/plan'),
      headers: await _authHeaders(),
    );
    return jsonDecode(response.body);
  }
}