// lib/providers/analysis_provider.dart
// Manages the Experta engine analysis result.
// Called by Dashboard and Insights screens.
// A single analyze() call returns everything both screens need.

import 'package:flutter/material.dart';
import '../data/remote/api_client.dart';
import '../models/analysis_result_model.dart';

class AnalysisProvider extends ChangeNotifier {
  AnalysisResultModel? _result;
  bool _isLoading = false;
  String? _errorMessage;

  // ─── Getters ─────────────────────────────────────────────────────────────────
  AnalysisResultModel? get result => _result;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get hasResult => _result != null;

  // ─── Analyze ─────────────────────────────────────────────────────────────────
  /// Calls POST /api/analyze and stores the full result.
  /// If the backend returns has_data: false (no transactions yet),
  /// _result is left null so the dashboard shows the empty card prompt.
  /// Returns true on success.
  Future<bool> analyze({int? month, int? year}) async {
    _setLoading(true);
    try {
      final data = await ApiClient.analyze(month: month, year: year);

      // No-data guard — new account or month with no transactions.
      // Leave _result as null so hasResult stays false and the dashboard
      // shows the empty card instead of a misleading score.
      if (data['has_data'] == false) {
        _result = null;
        _errorMessage = null;
        return true;
      }

      _result = AnalysisResultModel.fromJson(data);
      _errorMessage = null;
      return true;
    } on ApiException catch (e) {
      _errorMessage = e.message;
      return false;
    } catch (e, stackTrace) {
      print('ANALYSIS ERROR: $e');
      print('STACK: $stackTrace');
      _errorMessage = 'Analysis failed. Check your connection.';
      return false;
    }finally {
      _setLoading(false);
    }
  }

  // ─── Clear ───────────────────────────────────────────────────────────────────
  /// Called on logout to wipe any cached analysis result.
  void clear() {
    _result = null;
    _errorMessage = null;
    notifyListeners();
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