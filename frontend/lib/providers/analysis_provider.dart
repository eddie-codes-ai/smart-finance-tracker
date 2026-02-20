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
  /// Optionally pass month/year — defaults to current month on backend.
  /// Returns true on success.
  Future<bool> analyze({int? month, int? year}) async {
    _setLoading(true);
    try {
      final data = await ApiClient.analyze(month: month, year: year);
      _result = AnalysisResultModel.fromJson(data);
      _errorMessage = null;
      return true;
    } on ApiException catch (e) {
      _errorMessage = e.message;
      return false;
    } catch (e) {
      _errorMessage = 'Analysis failed. Check your connection.';
      return false;
    } finally {
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