// lib/providers/guardian_provider.dart
// Manages guardian link status and report history.
// Covers: link, unlink, status check, manual notify, and report fetch.

import 'package:flutter/material.dart';
import '../data/remote/api_client.dart';
import '../models/guardian_model.dart';

class GuardianProvider extends ChangeNotifier {
  GuardianModel? _guardian;
  GuardianReportModel? _latestReport;
  bool _isLinked = false;
  bool _isLoading = false;
  String? _errorMessage;
  String? _successMessage;

  // ─── Getters ─────────────────────────────────────────────────────────────────
  GuardianModel? get guardian => _guardian;
  GuardianReportModel? get latestReport => _latestReport;
  bool get isLinked => _isLinked;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  String? get successMessage => _successMessage;

  // ─── Fetch Status ─────────────────────────────────────────────────────────────
  /// Called when GuardianScreen loads to check if a guardian is linked.
  Future<void> fetchStatus() async {
    _setLoading(true);
    try {
      final data = await ApiClient.getGuardianStatus();
      _isLinked = data['linked'] ?? false;
      _guardian = _isLinked && data['guardian'] != null
          ? GuardianModel.fromJson(data['guardian'])
          : null;
      _errorMessage = null;
    } on ApiException catch (e) {
      _errorMessage = e.message;
    } catch (e) {
      _errorMessage = 'Failed to fetch guardian status.';
    } finally {
      _setLoading(false);
    }
  }

  // ─── Link ────────────────────────────────────────────────────────────────────
  Future<bool> linkGuardian(String phoneNumber) async {
    _setLoading(true);
    try {
      final data = await ApiClient.linkGuardian(phoneNumber: phoneNumber);
      _guardian = GuardianModel.fromJson(data['guardian']);
      _isLinked = true;
      _successMessage = 'Guardian linked successfully.';
      _errorMessage = null;
      return true;
    } on ApiException catch (e) {
      _errorMessage = e.message;
      return false;
    } catch (e) {
      _errorMessage = 'Failed to link guardian. Check your connection.';
      return false;
    } finally {
      _setLoading(false);
    }
  }

  // ─── Unlink ──────────────────────────────────────────────────────────────────
  Future<bool> unlinkGuardian() async {
    _setLoading(true);
    try {
      await ApiClient.unlinkGuardian();
      _guardian = null;
      _isLinked = false;
      _successMessage = 'Guardian unlinked.';
      _errorMessage = null;
      return true;
    } on ApiException catch (e) {
      _errorMessage = e.message;
      return false;
    } catch (e) {
      _errorMessage = 'Failed to unlink guardian. Check your connection.';
      return false;
    } finally {
      _setLoading(false);
    }
  }

  // ─── Manual Notify ───────────────────────────────────────────────────────────
  /// No cooldown applies — student explicitly triggered this.
  Future<bool> notifyGuardian({int? month, int? year}) async {
    _setLoading(true);
    try {
      final data = await ApiClient.notifyGuardian(month: month, year: year);
      _successMessage = 'Guardian notified via ${data['channel']}.';
      _errorMessage = null;
      return true;
    } on ApiException catch (e) {
      _errorMessage = e.message;
      return false;
    } catch (e) {
      _errorMessage = 'Failed to notify guardian. Check your connection.';
      return false;
    } finally {
      _setLoading(false);
    }
  }

  // ─── Fetch Report ────────────────────────────────────────────────────────────
  Future<void> fetchLatestReport() async {
    _setLoading(true);
    try {
      final data = await ApiClient.getGuardianReport();
      _latestReport = data['report'] != null
          ? GuardianReportModel.fromJson(data['report'])
          : null;
      _errorMessage = null;
    } on ApiException catch (e) {
      _errorMessage = e.message;
    } catch (e) {
      _errorMessage = 'Failed to fetch report.';
    } finally {
      _setLoading(false);
    }
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────────
  void clearMessages() {
    _errorMessage = null;
    _successMessage = null;
    notifyListeners();
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }
}