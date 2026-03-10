// lib/providers/expense_provider.dart
// Manages expense records for the currently viewed month/year.
// Also exposes per-category totals used by the budget and reports screens.

import 'package:flutter/material.dart';
import '../data/remote/api_client.dart';
import '../models/expense_model.dart';

class ExpenseProvider extends ChangeNotifier {
  List<ExpenseModel> _records = [];
  bool _isLoading = false;
  String? _errorMessage;

  int _month = DateTime.now().month;
  int _year = DateTime.now().year;

  // ─── Getters ─────────────────────────────────────────────────────────────────
  List<ExpenseModel> get records => _records;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  int get month => _month;
  int get year => _year;

  /// Total expenses for the loaded period — includes ALL expense types
  /// so the display matches what the user actually spent.
  /// One-time expense filtering is handled by analysis_service.py on the
  /// backend, where it affects daily budget calculations only.
  double get total => _records.fold(0, (sum, e) => sum + e.amount);

  /// Per-category totals — excludes one-time expenses to stay consistent
  /// with analysis_service.py behaviour for budget variance display.
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
    _year = year ?? _year;
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
  }) async {
    _setLoading(true);
    try {
      final data = await ApiClient.addExpense(
        amount: amount,
        category: category,
        description: description,
        expenseType: expenseType,
        recurrenceInterval: recurrenceInterval,
      );
      final newRecord = ExpenseModel.fromJson(data['expense']);
      _records.insert(0, newRecord);
      _errorMessage = null;
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