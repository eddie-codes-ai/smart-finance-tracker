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

  /// Called when the session is genuinely over — the refresh token has expired
  /// or been revoked — so the app can clear its state and return to login.
  ///
  /// A callback rather than a direct navigation call, so this layer stays free
  /// of any dependency on routing. app.dart wires it up once.
  static Future<void> Function()? onSessionExpired;

  /// The refresh currently in flight, if any.
  ///
  /// The dashboard fires analyze, getIncome and getExpenses together, so three
  /// requests can hit a 401 within milliseconds of each other. Without this
  /// they would each start a refresh, and the last to finish would overwrite
  /// the token the others had already stored.
  static Future<bool>? _refreshInFlight;

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
  ///
  /// The access token expires after an hour. When the server says so, this
  /// exchanges the refresh token for a new one and replays the request **once**
  /// — so the expiry is invisible — and gives up if that fails, rather than
  /// looping against a server that has already refused.
  static Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, dynamic>? query,
    bool authenticated = true,
  }) async {
    try {
      return await _sendOnce(method, path,
          body: body, query: query, authenticated: authenticated);
    } on ApiException catch (e) {
      if (!e.sessionExpired || !authenticated) rethrow;

      final refreshed = await _refreshAccessToken();
      if (!refreshed) {
        // The refresh token is gone too: the session is genuinely over.
        await onSessionExpired?.call();
        throw ApiException(
          'Your session has expired. Please sign in again.',
          statusCode: 401,
          sessionExpired: true,
        );
      }
      // One replay only. If this 401s again, it is not an expiry problem.
      return await _sendOnce(method, path,
          body: body, query: query, authenticated: authenticated);
    }
  }

  /// Exchange the refresh token for a new access token.
  ///
  /// Concurrent callers share one in-flight refresh rather than each starting
  /// their own and racing to overwrite the result.
  static Future<bool> _refreshAccessToken() {
    return _refreshInFlight ??= _performRefresh()
        .whenComplete(() => _refreshInFlight = null);
  }

  static Future<bool> _performRefresh() async {
    final refreshToken = await SecureStorage.getRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) return false;

    try {
      final response = await http
          .post(Uri.parse('${AppConstants.baseUrl}/auth/refresh'),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $refreshToken',
              })
          .timeout(_timeout);

      if (response.statusCode < 200 || response.statusCode >= 300) return false;

      final token = _decode(response)['token'] as String?;
      if (token == null || token.isEmpty) return false;

      await SecureStorage.saveToken(token);
      return true;
    } catch (_) {
      // A refresh that cannot reach the server is not proof the session ended,
      // but there is nothing further to try on this request either.
      return false;
    }
  }

  static Future<Map<String, dynamic>> _sendOnce(
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

  /// Serializes a DateTime as UTC, which is the only frame the server stores.
  ///
  /// The user picks a date in their own time; sending that wall-clock reading
  /// unconverted would file it three hours out, because the server reads every
  /// incoming timestamp as UTC.
  static String _isoUtc(DateTime moment) => moment.toUtc().toIso8601String();

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
    String? timezone,
  }) {
    return _send('POST', '/auth/register', authenticated: false, body: {
      'username': username,
      'password': password,
      if (email != null && email.isNotEmpty) 'email': email,
      if (timezone != null && timezone.isNotEmpty) 'timezone': timezone,
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
    String? timezone,
  }) {
    return _send('PUT', '/auth/profile', body: {
      if (username != null && username.isNotEmpty) 'username': username,
      if (email != null && email.isNotEmpty) 'email': email,
      if (newPassword != null && newPassword.isNotEmpty) 'new_password': newPassword,
      if (currentPassword != null && currentPassword.isNotEmpty)
        'current_password': currentPassword,
      if (timezone != null && timezone.isNotEmpty) 'timezone': timezone,
    });
  }

  static Future<Map<String, dynamic>> deleteAccount({required String password}) {
    return _send('DELETE', '/auth/account', body: {'password': password});
  }

  /// The signed-in user, used to restore a session on app start.
  ///
  /// The splash screen used to decide it was signed in purely because a token
  /// string existed in storage, without checking whether it was still valid.
  static Future<Map<String, dynamic>> me() {
    return _send('GET', '/auth/me');
  }

  /// End every session for this account, server-side.
  static Future<Map<String, dynamic>> logout() {
    return _send('POST', '/auth/logout');
  }

  static Future<Map<String, dynamic>> cancelDeletion() {
    return _send('POST', '/auth/cancel-deletion');
  }

  /// Every IANA zone the server accepts, for the profile picker. Fetched
  /// rather than bundled so the list can never drift from what the backend
  /// will actually take.
  static Future<Map<String, dynamic>> getTimezones() {
    return _send('GET', '/timezones');
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

  /// [mpesaCode] and [dateAdded] are for imported M-Pesa messages: the code
  /// lets the server refuse a second import of the same message, and the date
  /// keeps the transaction on the day it actually happened.
  static Future<Map<String, dynamic>> addIncome({
    required double amount,
    required String incomeType,
    String description = '',
    String? mpesaCode,
    DateTime? dateAdded,
  }) {
    return _send('POST', '/income', body: {
      'amount': amount,
      'income_type': incomeType,
      'description': description,
      if (mpesaCode != null && mpesaCode.isNotEmpty) 'mpesa_code': mpesaCode,
      if (dateAdded != null) 'date_added': _isoUtc(dateAdded),
    });
  }

  static Future<Map<String, dynamic>> getIncome({int? month, int? year}) {
    return _send('GET', '/income', query: _period(month, year));
  }

  /// Partial update — only the arguments you pass are changed. Anything left
  /// null keeps its stored value, including date_added.
  static Future<Map<String, dynamic>> updateIncome({
    required int id,
    double? amount,
    String? incomeType,
    String? description,
    DateTime? dateAdded,
  }) {
    return _send('PUT', '/income/$id', body: {
      if (amount != null) 'amount': amount,
      if (incomeType != null) 'income_type': incomeType,
      if (description != null) 'description': description,
      if (dateAdded != null) 'date_added': _isoUtc(dateAdded),
    });
  }

  static Future<Map<String, dynamic>> deleteIncome(int id) {
    return _send('DELETE', '/income/$id');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // EXPENSES
  // ═══════════════════════════════════════════════════════════════════════════

  /// [mpesaCode] and [dateAdded] are for imported M-Pesa messages: the code
  /// lets the server refuse a second import of the same message, and the date
  /// keeps the transaction on the day it actually happened.
  static Future<Map<String, dynamic>> addExpense({
    required double amount,
    required String category,
    String description = '',
    String expenseType = 'daily',
    String? recurrenceInterval,
    String? mpesaCode,
    DateTime? dateAdded,
  }) {
    return _send('POST', '/expenses', body: {
      'amount': amount,
      'category': category,
      'description': description,
      'expense_type': expenseType,
      'recurrence_interval': recurrenceInterval,
      if (mpesaCode != null && mpesaCode.isNotEmpty) 'mpesa_code': mpesaCode,
      if (dateAdded != null) 'date_added': _isoUtc(dateAdded),
    });
  }

  /// Which of these M-Pesa codes this user has already imported, so the import
  /// screen can mark them rather than letting the user tap one and be refused.
  static Future<Map<String, dynamic>> checkImportedMpesaCodes(List<String> codes) {
    return _send('POST', '/mpesa/imported', body: {'codes': codes});
  }

  static Future<Map<String, dynamic>> getExpenses({int? month, int? year}) {
    return _send('GET', '/expenses', query: _period(month, year));
  }

  /// Partial update — only the arguments you pass are changed. Anything left
  /// null keeps its stored value, including date_added.
  static Future<Map<String, dynamic>> updateExpense({
    required int id,
    double? amount,
    String? category,
    String? description,
    String? expenseType,
    DateTime? dateAdded,
  }) {
    return _send('PUT', '/expenses/$id', body: {
      if (amount != null) 'amount': amount,
      if (category != null) 'category': category,
      if (description != null) 'description': description,
      if (expenseType != null) 'expense_type': expenseType,
      if (dateAdded != null) 'date_added': _isoUtc(dateAdded),
    });
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
