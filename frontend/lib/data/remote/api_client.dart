// lib/data/remote/api_client.dart
// All methods are STATIC — providers call them as ApiClient.methodName()
//
// Every request goes through _send(), which is the only place that talks to
// http. It checks the status code, applies a timeout, and throws ApiException
// carrying the server's own message. Callers get a decoded body on success or
// an exception on failure — never a decoded error page that looks like success.

import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:frontend/data/local/secure_storage.dart';
import 'package:frontend/core/constants.dart';

// ─── Custom exception used by providers ───────────────────────────────────────
class ApiException implements Exception {
  final String message;
  final int? statusCode;

  /// True when the server said the JWT expired, so the app should sign out
  /// and send the user back to login rather than showing an error.
  final bool sessionExpired;

  ApiException(this.message, {this.statusCode, this.sessionExpired = false});

  /// 401/403 — the request was rejected because of who (or whether) we are.
  bool get isAuthFailure => statusCode == 401 || statusCode == 403;

  @override
  String toString() => message;
}

class ApiClient {
  /// Long enough for a cold start on Railway's free tier, short enough that a
  /// dead connection doesn't hang the UI forever.
  static const Duration _timeout = Duration(seconds: 30);

  static Future<Map<String, String>> _headers({bool authenticated = true}) async {
    final headers = {'Content-Type': 'application/json'};
    if (authenticated) {
      final token = await SecureStorage.getToken();
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
    }
    return headers;
  }

  /// The single request path for the whole app.
  ///
  /// Throws [ApiException] on timeout, transport failure, a non-2xx status, or
  /// a body that isn't JSON. Returns the decoded body on success.
  static Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, dynamic>? query,
    bool authenticated = true,
  }) async {
    var uri = Uri.parse('${AppConstants.baseUrl}$path');
    if (query != null && query.isNotEmpty) {
      uri = uri.replace(
        queryParameters: query.map((k, v) => MapEntry(k, '$v')),
      );
    }

    final headers = await _headers(authenticated: authenticated);
    final encoded = body == null ? null : jsonEncode(body);

    http.Response response;
    try {
      final Future<http.Response> request;
      switch (method) {
        case 'GET':
          request = http.get(uri, headers: headers);
          break;
        case 'POST':
          request = http.post(uri, headers: headers, body: encoded);
          break;
        case 'PUT':
          request = http.put(uri, headers: headers, body: encoded);
          break;
        case 'DELETE':
          request = http.delete(uri, headers: headers, body: encoded);
          break;
        default:
          throw ArgumentError('Unsupported HTTP method: $method');
      }
      response = await request.timeout(_timeout);
    } on TimeoutException {
      throw ApiException('The server took too long to respond. Please try again.');
    } on http.ClientException catch (e) {
      throw ApiException('Could not reach the server. Check your connection.\n${e.message}');
    } catch (e) {
      throw ApiException('Could not reach the server. Check your connection.');
    }

    final decoded = _decode(response);
    final status = response.statusCode;

    if (status >= 200 && status < 300) return decoded;

    throw ApiException(
      decoded['message'] as String? ?? _fallbackMessage(status),
      statusCode: status,
      sessionExpired: decoded['token_expired'] == true,
    );
  }

  /// Decodes a JSON object body, tolerating an empty or non-JSON response so
  /// that the status code still decides the outcome.
  static Map<String, dynamic> _decode(http.Response response) {
    if (response.body.isEmpty) return <String, dynamic>{};
    try {
      final parsed = jsonDecode(response.body);
      return parsed is Map<String, dynamic> ? parsed : <String, dynamic>{};
    } on FormatException {
      return <String, dynamic>{};
    }
  }

  static String _fallbackMessage(int status) {
    if (status == 401) return 'Your session has expired. Please sign in again.';
    if (status == 403) return 'You do not have permission to do that.';
    if (status == 404) return 'That record no longer exists.';
    if (status == 409) return 'That already exists.';
    if (status >= 500) return 'The server had a problem. Please try again shortly.';
    return 'Request failed ($status).';
  }

  // Month/year query shared by every period-scoped GET.
  static Map<String, dynamic> _period(int? month, int? year) {
    final now = DateTime.now();
    return {'month': month ?? now.month, 'year': year ?? now.year};
  }

  static String _monthYear(String? monthYear) {
    if (monthYear != null) return monthYear;
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}';
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // AUTH
  // ═══════════════════════════════════════════════════════════════════════════

  static Future<Map<String, dynamic>> register(
    String username,
    String password, {
    String? email,
  }) {
    return _send('POST', '/auth/register', authenticated: false, body: {
      'username': username,
      'password': password,
      if (email != null && email.isNotEmpty) 'email': email,
    });
  }

  static Future<Map<String, dynamic>> login(String username, String password) {
    return _send('POST', '/auth/login', authenticated: false, body: {
      'username': username,
      'password': password,
    });
  }

  static Future<Map<String, dynamic>> googleSignIn(String idToken) {
    return _send('POST', '/auth/google',
        authenticated: false, body: {'id_token': idToken});
  }

  static Future<Map<String, dynamic>> forgotPassword(String email) {
    return _send('POST', '/auth/forgot-password',
        authenticated: false, body: {'email': email});
  }

  static Future<Map<String, dynamic>> resetPassword(
    String email,
    String code,
    String newPassword,
  ) {
    return _send('POST', '/auth/reset-password', authenticated: false, body: {
      'email': email,
      'code': code,
      'new_password': newPassword,
    });
  }

  static Future<Map<String, dynamic>> updateProfile({
    String? username,
    String? email,
    String? newPassword,
    String? currentPassword,
  }) {
    return _send('PUT', '/auth/profile', body: {
      if (username != null && username.isNotEmpty) 'username': username,
      if (email != null && email.isNotEmpty) 'email': email,
      if (newPassword != null && newPassword.isNotEmpty) 'new_password': newPassword,
      if (currentPassword != null && currentPassword.isNotEmpty)
        'current_password': currentPassword,
    });
  }

  static Future<Map<String, dynamic>> deleteAccount({required String password}) {
    return _send('DELETE', '/auth/account', body: {'password': password});
  }

  static Future<Map<String, dynamic>> cancelDeletion() {
    return _send('POST', '/auth/cancel-deletion');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CATEGORIES
  // ═══════════════════════════════════════════════════════════════════════════

  static Future<Map<String, dynamic>> getCategories() {
    return _send('GET', '/categories');
  }

  static Future<Map<String, dynamic>> addCategory(String name) {
    return _send('POST', '/categories', body: {'name': name});
  }

  static Future<Map<String, dynamic>> deleteCategory(String name) {
    return _send('DELETE', '/categories/${Uri.encodeComponent(name)}');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // INCOME TYPES
  // ═══════════════════════════════════════════════════════════════════════════

  static Future<Map<String, dynamic>> getIncomeTypes() {
    return _send('GET', '/income-types');
  }

  static Future<Map<String, dynamic>> addIncomeType(String name) {
    return _send('POST', '/income-types', body: {'name': name});
  }

  static Future<Map<String, dynamic>> deleteIncomeType(String name) {
    return _send('DELETE', '/income-types/${Uri.encodeComponent(name)}');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // INCOME
  // ═══════════════════════════════════════════════════════════════════════════

  static Future<Map<String, dynamic>> addIncome({
    required double amount,
    required String incomeType,
    String description = '',
  }) {
    return _send('POST', '/income', body: {
      'amount': amount,
      'income_type': incomeType,
      'description': description,
    });
  }

  static Future<Map<String, dynamic>> getIncome({int? month, int? year}) {
    return _send('GET', '/income', query: _period(month, year));
  }

  static Future<Map<String, dynamic>> deleteIncome(int id) {
    return _send('DELETE', '/income/$id');
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
  }) {
    return _send('POST', '/expenses', body: {
      'amount': amount,
      'category': category,
      'description': description,
      'expense_type': expenseType,
      'recurrence_interval': recurrenceInterval,
    });
  }

  static Future<Map<String, dynamic>> getExpenses({int? month, int? year}) {
    return _send('GET', '/expenses', query: _period(month, year));
  }

  static Future<Map<String, dynamic>> deleteExpense(int id) {
    return _send('DELETE', '/expenses/$id');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUDGETS
  // ═══════════════════════════════════════════════════════════════════════════

  static Future<Map<String, dynamic>> setBudget({
    required String category,
    required double limit,
    String? monthYear,
  }) {
    return _send('POST', '/budgets', body: {
      'category': category,
      'limit': limit,
      'month_year': _monthYear(monthYear),
    });
  }

  static Future<Map<String, dynamic>> getBudgets({String? monthYear}) {
    return _send('GET', '/budgets', query: {'month_year': _monthYear(monthYear)});
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SAVINGS GOALS
  // ═══════════════════════════════════════════════════════════════════════════

  static Future<Map<String, dynamic>> addGoal({
    required String name,
    required double goalAmount,
    required String dueDate,
  }) {
    return _send('POST', '/goals', body: {
      'name': name,
      'goal_amount': goalAmount,
      'due_date': dueDate,
    });
  }

  static Future<Map<String, dynamic>> getGoals() {
    return _send('GET', '/goals');
  }

  static Future<Map<String, dynamic>> closeGoal(int id) {
    return _send('DELETE', '/goals/$id');
  }

  static Future<Map<String, dynamic>> addContribution({
    required int goalId,
    required double amount,
    String? note,
  }) {
    return _send('POST', '/goals/$goalId/contribute', body: {
      'amount': amount,
      if (note != null && note.isNotEmpty) 'note': note,
    });
  }

  static Future<Map<String, dynamic>> getContributions(int goalId) {
    return _send('GET', '/goals/$goalId/contributions');
  }

  static Future<Map<String, dynamic>> getAllContributions({int? month, int? year}) {
    return _send('GET', '/contributions', query: _period(month, year));
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ANALYSIS
  // ═══════════════════════════════════════════════════════════════════════════

  static Future<Map<String, dynamic>> analyze({int? month, int? year}) {
    return _send('POST', '/analyze', body: _period(month, year));
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // GUARDIAN
  // ═══════════════════════════════════════════════════════════════════════════

  static Future<Map<String, dynamic>> linkGuardian({required String phoneNumber}) {
    return _send('POST', '/guardian/link', body: {'phone_number': phoneNumber});
  }

  static Future<Map<String, dynamic>> getGuardianStatus() {
    return _send('GET', '/guardian/status');
  }

  static Future<Map<String, dynamic>> unlinkGuardian() {
    return _send('DELETE', '/guardian/unlink');
  }

  static Future<Map<String, dynamic>> notifyGuardian({int? month, int? year}) {
    return _send('POST', '/guardian/notify', body: _period(month, year));
  }

  static Future<Map<String, dynamic>> getGuardianReport() {
    return _send('GET', '/guardian/report');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELB PLANNER
  // ═══════════════════════════════════════════════════════════════════════════

  static Future<Map<String, dynamic>> getHelbPlan() {
    return _send('GET', '/helb/plan');
  }

  static Future<Map<String, dynamic>> saveHelbPlan({
    required String semesterName,
    required double helbAmount,
    required String startDate,
    required String endDate,
    required Map<String, double> allocations,
  }) {
    return _send('POST', '/helb/plan', body: {
      'semester_name': semesterName,
      'helb_amount': helbAmount,
      'start_date': startDate,
      'end_date': endDate,
      'allocations': allocations,
    });
  }

  static Future<Map<String, dynamic>> deleteHelbPlan() {
    return _send('DELETE', '/helb/plan');
  }
}
