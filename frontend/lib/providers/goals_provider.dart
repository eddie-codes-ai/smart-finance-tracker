// lib/providers/goals_provider.dart
// Manages savings goals. Supports multiple active goals per student.

import 'package:flutter/material.dart';
import '../data/remote/api_client.dart';
import '../models/savings_goal_model.dart';

class GoalsProvider extends ChangeNotifier {
  List<SavingsGoalModel> _goals = [];
  bool _isLoading = false;
  String? _errorMessage;

  // ─── Getters ─────────────────────────────────────────────────────────────────
  List<SavingsGoalModel> get goals => _goals;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get hasGoals => _goals.isNotEmpty;

  /// The primary goal — the first active one.
  /// Matches analysis_service.py: primary_goal = goals[0] if goals else None
  SavingsGoalModel? get primaryGoal => _goals.isNotEmpty ? _goals.first : null;

  // ─── Fetch ───────────────────────────────────────────────────────────────────
  Future<void> fetchGoals() async {
    _setLoading(true);
    try {
      final data = await ApiClient.getGoals();
      _goals = (data['goals'] as List)
          .map((e) => SavingsGoalModel.fromJson(e))
          .toList();
      _errorMessage = null;
    } on ApiException catch (e) {
      _errorMessage = e.message;
    } catch (e) {
      _errorMessage = 'Failed to load goals. Check your connection.';
    } finally {
      _setLoading(false);
    }
  }

  // ─── Add ─────────────────────────────────────────────────────────────────────
  Future<bool> addGoal({
    required String name,
    required double goalAmount,
    required String dueDate, // "YYYY-MM-DD"
  }) async {
    _setLoading(true);
    try {
      final data = await ApiClient.addGoal(
        name: name,
        goalAmount: goalAmount,
        dueDate: dueDate,
      );
      final newGoal = SavingsGoalModel.fromJson(data['goal']);
      _goals.add(newGoal);
      _errorMessage = null;
      return true;
    } on ApiException catch (e) {
      _errorMessage = e.message;
      return false;
    } catch (e) {
      _errorMessage = 'Failed to create goal. Check your connection.';
      return false;
    } finally {
      _setLoading(false);
    }
  }

  // ─── Close (Soft Delete) ─────────────────────────────────────────────────────
  /// Sets is_active = false on the backend, removes from local list.
  Future<bool> closeGoal(int id) async {
    _setLoading(true);
    try {
      await ApiClient.closeGoal(id);
      _goals.removeWhere((g) => g.id == id);
      _errorMessage = null;
      return true;
    } on ApiException catch (e) {
      _errorMessage = e.message;
      return false;
    } catch (e) {
      _errorMessage = 'Failed to close goal. Check your connection.';
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