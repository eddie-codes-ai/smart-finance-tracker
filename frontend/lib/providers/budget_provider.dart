// lib/providers/budget_provider.dart
// Manages budget limits per category per month.
// The upsert pattern from the backend means set and update are the same call.

import 'package:flutter/material.dart';
import '../data/remote/api_client.dart';
import '../models/budget_model.dart';

class BudgetProvider extends ChangeNotifier {
  List<BudgetModel> _budgets = [];
  bool _isLoading = false;
  String? _errorMessage;

  String _monthYear = _currentMonthYear();

  // ─── Getters ─────────────────────────────────────────────────────────────────
  List<BudgetModel> get budgets => _budgets;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  String get monthYear => _monthYear;

  /// Quick lookup: get budget limit for a specific category.
  /// Returns null if no budget has been set for that category.
  double? limitFor(String category) {
    try {
      return _budgets.firstWhere((b) => b.category == category).limit;
    } catch (_) {
      return null;
    }
  }

  // ─── Fetch ───────────────────────────────────────────────────────────────────
  Future<void> fetchBudgets({String? monthYear}) async {
    _monthYear = monthYear ?? _monthYear;
    _setLoading(true);
    try {
      final data = await ApiClient.getBudgets(monthYear: _monthYear);
      _budgets = (data['budgets'] as List)
          .map((e) => BudgetModel.fromJson(e))
          .toList();
      _errorMessage = null;
    } on ApiException catch (e) {
      _errorMessage = e.message;
    } catch (e) {
      _errorMessage = 'Failed to load budgets. Check your connection.';
    } finally {
      _setLoading(false);
    }
  }

  // ─── Set (Create or Update) ──────────────────────────────────────────────────
  /// The backend upserts — so this handles both creating a new budget
  /// and updating an existing one for the same category/month.
  Future<bool> setBudget({
    required String category,
    required double limit,
    String? monthYear,
  }) async {
    final targetMonth = monthYear ?? _monthYear;
    _setLoading(true);
    try {
      await ApiClient.setBudget(
        category: category,
        limit: limit,
        monthYear: targetMonth,
      );
      // Refresh the list to reflect the upsert result.
      await fetchBudgets(monthYear: targetMonth);
      _errorMessage = null;
      return true;
    } on ApiException catch (e) {
      _errorMessage = e.message;
      return false;
    } catch (e) {
      _errorMessage = 'Failed to save budget. Check your connection.';
      return false;
    } finally {
      _setLoading(false);
    }
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────────
  static String _currentMonthYear() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}';
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }
}