// lib/data/remote/api_client.dart
// Central HTTP client for all communication with the Flask backend.
// Automatically attaches the JWT token to every protected request.
// All endpoints from routes.py are covered here.
//
// Response pattern from Flask:
//   Success: { "status": "success", ...data }
//   Error:   { "status": "error", "message": "..." }

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../core/constants.dart';
import '../local/secure_storage.dart';

class ApiClient {
  static const String _base = AppConstants.baseUrl;

  // ─── Private Helpers ──────────────────────────────────────────────────────

  static Map<String, String> _publicHeaders() {
    return {'Content-Type': 'application/json'};
  }

  /// Reads token from secure storage and attaches it as Bearer.
  /// All HELB endpoints now use this — fixes the 422 issue.
  static Future<Map<String, String>> _authHeaders() async {
    final token = await SecureStorage.getToken();
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  static Map<String, dynamic> _handle(http.Response response) {
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (body['status'] == 'error') {
      throw ApiException(body['message'] ?? 'Unknown error', response.statusCode);
    }
    return body;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // AUTH
  // ═══════════════════════════════════════════════════════════════════════════

  static Future<Map<String, dynamic>> register({
    required String username,
    required String password,
  }) async {
    final response = await http.post(
      Uri.parse('$_base/auth/register'),
      headers: _publicHeaders(),
      body: jsonEncode({'username': username, 'password': password}),
    );
    return _handle(response);
  }

  static Future<Map<String, dynamic>> login({
    required String username,
    required String password,
  }) async {
    final response = await http.post(
      Uri.parse('$_base/auth/login'),
      headers: _publicHeaders(),
      body: jsonEncode({'username': username, 'password': password}),
    );
    return _handle(response);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // INCOME
  // ═══════════════════════════════════════════════════════════════════════════

  static Future<Map<String, dynamic>> addIncome({
    required double amount,
    required String incomeType,
    required String description,
  }) async {
    final response = await http.post(
      Uri.parse('$_base/income'),
      headers: await _authHeaders(),
      body: jsonEncode({
        'amount': amount,
        'income_type': incomeType,
        'description': description,
      }),
    );
    return _handle(response);
  }

  static Future<Map<String, dynamic>> getIncome({
    required int month,
    required int year,
  }) async {
    final response = await http.get(
      Uri.parse('$_base/income?month=$month&year=$year'),
      headers: await _authHeaders(),
    );
    return _handle(response);
  }

  static Future<Map<String, dynamic>> deleteIncome(int id) async {
    final response = await http.delete(
      Uri.parse('$_base/income/$id'),
      headers: await _authHeaders(),
    );
    return _handle(response);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // EXPENSES
  // ═══════════════════════════════════════════════════════════════════════════

  static Future<Map<String, dynamic>> addExpense({
    required double amount,
    required String category,
    required String description,
    required String expenseType,
    String? recurrenceInterval,
  }) async {
    final response = await http.post(
      Uri.parse('$_base/expenses'),
      headers: await _authHeaders(),
      body: jsonEncode({
        'amount': amount,
        'category': category,
        'description': description,
        'expense_type': expenseType,
        'recurrence_interval': recurrenceInterval,
      }),
    );
    return _handle(response);
  }

  static Future<Map<String, dynamic>> getExpenses({
    required int month,
    required int year,
  }) async {
    final response = await http.get(
      Uri.parse('$_base/expenses?month=$month&year=$year'),
      headers: await _authHeaders(),
    );
    return _handle(response);
  }

  static Future<Map<String, dynamic>> deleteExpense(int id) async {
    final response = await http.delete(
      Uri.parse('$_base/expenses/$id'),
      headers: await _authHeaders(),
    );
    return _handle(response);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUDGETS
  // ═══════════════════════════════════════════════════════════════════════════

  static Future<Map<String, dynamic>> setBudget({
    required String category,
    required double limit,
    required String monthYear,
  }) async {
    final response = await http.post(
      Uri.parse('$_base/budgets'),
      headers: await _authHeaders(),
      body: jsonEncode({
        'category': category,
        'limit': limit,
        'month_year': monthYear,
      }),
    );
    return _handle(response);
  }

  static Future<Map<String, dynamic>> getBudgets({
    required String monthYear,
  }) async {
    final response = await http.get(
      Uri.parse('$_base/budgets?month_year=$monthYear'),
      headers: await _authHeaders(),
    );
    return _handle(response);
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
      Uri.parse('$_base/goals'),
      headers: await _authHeaders(),
      body: jsonEncode({
        'name': name,
        'goal_amount': goalAmount,
        'due_date': dueDate,
      }),
    );
    return _handle(response);
  }

  static Future<Map<String, dynamic>> getGoals() async {
    final response = await http.get(
      Uri.parse('$_base/goals'),
      headers: await _authHeaders(),
    );
    return _handle(response);
  }

  static Future<Map<String, dynamic>> closeGoal(int id) async {
    final response = await http.delete(
      Uri.parse('$_base/goals/$id'),
      headers: await _authHeaders(),
    );
    return _handle(response);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ANALYSIS
  // ═══════════════════════════════════════════════════════════════════════════

  static Future<Map<String, dynamic>> analyze({
    int? month,
    int? year,
  }) async {
    final body = <String, dynamic>{};
    if (month != null) body['month'] = month;
    if (year != null) body['year'] = year;

    final response = await http.post(
      Uri.parse('$_base/analyze'),
      headers: await _authHeaders(),
      body: jsonEncode(body),
    );
    return _handle(response);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // GUARDIAN
  // ═══════════════════════════════════════════════════════════════════════════

  static Future<Map<String, dynamic>> linkGuardian({
    required String phoneNumber,
  }) async {
    final response = await http.post(
      Uri.parse('$_base/guardian/link'),
      headers: await _authHeaders(),
      body: jsonEncode({'phone_number': phoneNumber}),
    );
    return _handle(response);
  }

  static Future<Map<String, dynamic>> getGuardianStatus() async {
    final response = await http.get(
      Uri.parse('$_base/guardian/status'),
      headers: await _authHeaders(),
    );
    return _handle(response);
  }

  static Future<Map<String, dynamic>> unlinkGuardian() async {
    final response = await http.delete(
      Uri.parse('$_base/guardian/unlink'),
      headers: await _authHeaders(),
    );
    return _handle(response);
  }

  static Future<Map<String, dynamic>> notifyGuardian({
    int? month,
    int? year,
  }) async {
    final body = <String, dynamic>{};
    if (month != null) body['month'] = month;
    if (year != null) body['year'] = year;

    final response = await http.post(
      Uri.parse('$_base/guardian/notify'),
      headers: await _authHeaders(),
      body: jsonEncode(body),
    );
    return _handle(response);
  }

  static Future<Map<String, dynamic>> getGuardianReport() async {
    final response = await http.get(
      Uri.parse('$_base/guardian/report'),
      headers: await _authHeaders(),
    );
    return _handle(response);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELB PLAN
  // Uses the same _authHeaders() as all other endpoints — fixes the 422.
  // ═══════════════════════════════════════════════════════════════════════════

  /// POST /api/helb-plan — create or update the semester budget plan
  static Future<Map<String, dynamic>> saveHelbPlan({
    required String semesterName,
    required double helbAmount,
    required String startDate,
    required String endDate,
    required Map<String, double> allocations,
  }) async {
    final response = await http.post(
      Uri.parse('$_base/helb-plan'),
      headers: await _authHeaders(),
      body: jsonEncode({
        'semester_name': semesterName,
        'helb_amount':   helbAmount,
        'start_date':    startDate,
        'end_date':      endDate,
        'allocations':   allocations,
      }),
    );
    return _handle(response);
  }

  /// GET /api/helb-plan — fetch the student's current semester plan
  static Future<Map<String, dynamic>> getHelbPlan() async {
    final response = await http.get(
      Uri.parse('$_base/helb-plan'),
      headers: await _authHeaders(),
    );
    return _handle(response);
  }

  /// DELETE /api/helb-plan — permanently delete the semester plan
  static Future<Map<String, dynamic>> deleteHelbPlan() async {
    final response = await http.delete(
      Uri.parse('$_base/helb-plan'),
      headers: await _authHeaders(),
    );
    return _handle(response);
  }
}

// ─── ApiException ─────────────────────────────────────────────────────────────

class ApiException implements Exception {
  final String message;
  final int statusCode;

  ApiException(this.message, this.statusCode);

  @override
  String toString() => 'ApiException($statusCode): $message';
}