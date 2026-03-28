// lib/providers/expense_provider.dart
import 'package:flutter/material.dart';
import '../core/notification_service.dart';   // ← NEW IMPORT
import '../data/remote/api_client.dart';
import '../models/expense_model.dart';

class ExpenseProvider extends ChangeNotifier {
  List<ExpenseModel> _records = [];
  bool _isLoading = false;
  String? _errorMessage;

  int _month = DateTime.now().month;
  int _year  = DateTime.now().year;

  // ─── Getters ─────────────────────────────────────────────────────────────────
  List<ExpenseModel> get records     => _records;
  bool               get isLoading   => _isLoading;
  String?            get errorMessage => _errorMessage;
  int                get month        => _month;
  int                get year         => _year;

  double get total =>
      _records.fold(0, (sum, e) => sum + e.amount);

  Map<String, double> get categoryTotals {
    final Map<String, double> totals = {};
    for (final e in _records.where((e) => e.expenseType != 'one-time')) {
      totals[e.category] = (totals[e.category] ?? 0) + e.amount;
    }
    return totals;
  }

  // ─── Fetch ───────────────────────────────────────────────────────────────────
  Future<void> fetchExpenses({int? month, int? year}) async {
    _month = month ?? _month;
    _year  = year  ?? _year;
    _setLoading(true);
    try {
      final data = await ApiClient.getExpenses(month: _month, year: _year);
      _records = (data['expenses'] as List)
          .map((e) => ExpenseModel.fromJson(e))
          .toList();
      _errorMessage = null;
    } on ApiException catch (e) {
      _errorMessage = e.message;
    } catch (e) {
      _errorMessage = 'Failed to load expenses. Check your connection.';
    } finally {
      _setLoading(false);
    }
  }

  // ─── Add ─────────────────────────────────────────────────────────────────────
  Future<bool> addExpense({
    required double amount,
    required String category,
    required String description,
    required String expenseType,
    String? recurrenceInterval,
    double? budgetLimit,          // ← NEW: pass from UI if a budget is set
  }) async {
    _setLoading(true);
    try {
      // Snapshot the category total BEFORE the new expense is added.
      // One-time expenses are excluded to match categoryTotals logic.
      final double previousTotal =
          expenseType != 'one-time' ? (categoryTotals[category] ?? 0.0) : 0.0;

      final data = await ApiClient.addExpense(
        amount:              amount,
        category:            category,
        description:         description,
        expenseType:         expenseType,
        recurrenceInterval:  recurrenceInterval,
      );

      final newRecord = ExpenseModel.fromJson(data['expense']);
      _records.insert(0, newRecord);
      _errorMessage = null;

      // Fire a local notification if a budget limit was supplied
      // and the expense type affects the budget (not one-time).
      if (budgetLimit != null && expenseType != 'one-time') {
        final double newTotal = previousTotal + amount;
        await NotificationService.instance.checkAndNotify(
          category:      category,
          previousTotal: previousTotal,
          newTotal:      newTotal,
          limit:         budgetLimit,
        );
      }

      return true;
    } on ApiException catch (e) {
      _errorMessage = e.message;
      return false;
    } catch (e) {
      _errorMessage = 'Failed to add expense. Check your connection.';
      return false;
    } finally {
      _setLoading(false);
    }
  }

  // ─── Delete ──────────────────────────────────────────────────────────────────
  Future<bool> deleteExpense(int id) async {
    _setLoading(true);
    try {
      await ApiClient.deleteExpense(id);
      _records.removeWhere((r) => r.id == id);
      _errorMessage = null;
      return true;
    } on ApiException catch (e) {
      _errorMessage = e.message;
      return false;
    } catch (e) {
      _errorMessage = 'Failed to delete expense. Check your connection.';
      return false;
    } finally {
      _setLoading(false);
    }
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────────
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }
}