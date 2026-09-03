// lib/providers/income_provider.dart
// Manages income records for the currently viewed month/year.

import 'package:flutter/material.dart';
import '../data/remote/api_client.dart';
import '../models/income_model.dart';

class IncomeProvider extends ChangeNotifier {
  List<IncomeModel> _records = [];
  bool _isLoading = false;
  String? _errorMessage;

  // Tracks which month/year is currently loaded.
  int _month = DateTime.now().month;
  int _year = DateTime.now().year;

  // ─── Getters ─────────────────────────────────────────────────────────────────
  List<IncomeModel> get records => _records;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  int get month => _month;
  int get year => _year;

  /// Total income for the loaded period.
  double get total => _records.fold(0, (sum, r) => sum + r.amount);

  // ─── Fetch ───────────────────────────────────────────────────────────────────
  Future<void> fetchIncome({int? month, int? year}) async {
    _month = month ?? _month;
    _year = year ?? _year;
    _setLoading(true);
    try {
      final data = await ApiClient.getIncome(month: _month, year: _year);
      _records = (data['income'] as List)
          .map((e) => IncomeModel.fromJson(e))
          .toList();
      _errorMessage = null;
    } on ApiException catch (e) {
      _errorMessage = e.message;
    } catch (e) {
      _errorMessage = 'Failed to load income. Check your connection.';
    } finally {
      _setLoading(false);
    }
  }

  // ─── Add ─────────────────────────────────────────────────────────────────────
  /// Returns true on success.
  Future<bool> addIncome({
    required double amount,
    required String incomeType,
    required String description,
  }) async {
    _setLoading(true);
    try {
      final data = await ApiClient.addIncome(
        amount: amount,
        incomeType: incomeType,
        description: description,
      );
      // Insert the new record at the top of the list without a full refetch.
      final newRecord = IncomeModel.fromJson(data['income']);
      _records.insert(0, newRecord);
      _errorMessage = null;
      return true;
    } on ApiException catch (e) {
      _errorMessage = e.message;
      return false;
    } catch (e) {
      _errorMessage = 'Failed to add income. Check your connection.';
      return false;
    } finally {
      _setLoading(false);
    }
  }

  // ─── Update ──────────────────────────────────────────────────────────────────
  /// Updates an existing income record in place. Only the arguments you pass
  /// change; anything left null keeps its stored value, including the date.
  ///
  /// Returns true on success. On failure the record is left untouched on the
  /// server and [errorMessage] explains why.
  Future<bool> updateIncome({
    required int id,
    double? amount,
    String? incomeType,
    String? description,
    DateTime? dateAdded,
  }) async {
    _setLoading(true);
    try {
      final data = await ApiClient.updateIncome(
        id:          id,
        amount:      amount,
        incomeType:  incomeType,
        description: description,
        dateAdded:   dateAdded,
      );

      final updated = IncomeModel.fromJson(data['income']);
      final index   = _records.indexWhere((r) => r.id == id);
      if (index != -1) {
        // Replace in place to keep list order; drop it if a changed date moved
        // the record out of the month currently loaded.
        if (_isInLoadedPeriod(updated)) {
          _records[index] = updated;
        } else {
          _records.removeAt(index);
        }
      }
      _errorMessage = null;
      return true;
    } on ApiException catch (e) {
      _errorMessage = e.message;
      return false;
    } catch (e) {
      _errorMessage = 'Failed to save changes. Check your connection.';
      return false;
    } finally {
      _setLoading(false);
    }
  }

  /// True if the record still falls inside the month/year this provider holds.
  bool _isInLoadedPeriod(IncomeModel record) {
    final date = DateTime.tryParse(record.dateAdded);
    if (date == null) return true; // unparseable — keep it rather than hide it
    return date.month == _month && date.year == _year;
  }

  // ─── Delete ──────────────────────────────────────────────────────────────────
  /// Returns true on success.
  Future<bool> deleteIncome(int id) async {
    _setLoading(true);
    try {
      await ApiClient.deleteIncome(id);
      _records.removeWhere((r) => r.id == id);
      _errorMessage = null;
      return true;
    } on ApiException catch (e) {
      _errorMessage = e.message;
      return false;
    } catch (e) {
      _errorMessage = 'Failed to delete income. Check your connection.';
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