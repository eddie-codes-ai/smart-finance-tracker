// lib/providers/goals_provider.dart
// Manages savings goals and goal contributions.
// Supports multiple active goals per student.

import 'package:flutter/material.dart';
import '../data/remote/api_client.dart';
import '../models/savings_goal_model.dart';
import '../models/goal_contribution_model.dart';

class GoalsProvider extends ChangeNotifier {
  List<SavingsGoalModel> _goals = [];
  // Contributions keyed by goalId — loaded on demand when a goal is opened.
  final Map<int, List<GoalContributionModel>> _contributions = {};
  bool _isLoading = false;
  bool _isContributing = false;
  String? _errorMessage;

  // ─── Getters ─────────────────────────────────────────────────────────────────
  List<SavingsGoalModel> get goals        => _goals;
  bool get isLoading                      => _isLoading;
  bool get isContributing                 => _isContributing;
  String? get errorMessage                => _errorMessage;
  bool get hasGoals                       => _goals.isNotEmpty;

  /// The primary goal — the first active one.
  /// Matches analysis_service.py: primary_goal = goals[0] if goals else None
  SavingsGoalModel? get primaryGoal => _goals.isNotEmpty ? _goals.first : null;

  /// Contributions for a specific goal (empty list if not yet loaded).
  List<GoalContributionModel> contributionsFor(int goalId) =>
      _contributions[goalId] ?? [];

  // ─── Fetch Goals ─────────────────────────────────────────────────────────────
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

  // ─── Add Goal ─────────────────────────────────────────────────────────────────
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

  // ─── Close Goal (Soft Delete) ─────────────────────────────────────────────────
  Future<bool> closeGoal(int id) async {
    _setLoading(true);
    try {
      await ApiClient.closeGoal(id);
      _goals.removeWhere((g) => g.id == id);
      _contributions.remove(id);
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

  // ─── Add Contribution ─────────────────────────────────────────────────────────
  /// Adds a contribution toward a specific goal.
  /// On success, refreshes the goal in the local list so totalContributed
  /// updates immediately without a full fetchGoals() call.
  Future<bool> addContribution({
    required int goalId,
    required double amount,
    String? note,
  }) async {
    _isContributing = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final data = await ApiClient.addContribution(
        goalId: goalId,
        amount: amount,
        note: note,
      );

      // Update the goal in the local list with the refreshed version
      // that has the updated total_contributed from the backend.
      final updatedGoal = SavingsGoalModel.fromJson(data['goal']);
      final idx = _goals.indexWhere((g) => g.id == goalId);
      if (idx != -1) {
        _goals[idx] = updatedGoal;
      }

      // Append contribution to local cache if already loaded.
      final newContribution = GoalContributionModel.fromJson(data['contribution']);
      if (_contributions.containsKey(goalId)) {
        _contributions[goalId]!.insert(0, newContribution);
      }

      _errorMessage = null;
      return true;
    } on ApiException catch (e) {
      _errorMessage = e.message;
      return false;
    } catch (e) {
      _errorMessage = 'Failed to add contribution. Check your connection.';
      return false;
    } finally {
      _isContributing = false;
      notifyListeners();
    }
  }

  // ─── Fetch Contributions ──────────────────────────────────────────────────────
  /// Loads contribution history for a specific goal.
  /// Results are cached in _contributions[goalId].
  Future<void> fetchContributions(int goalId) async {
    _setLoading(true);
    try {
      final data = await ApiClient.getContributions(goalId);
      _contributions[goalId] = (data['contributions'] as List)
          .map((e) => GoalContributionModel.fromJson(e))
          .toList();
      _errorMessage = null;
    } on ApiException catch (e) {
      _errorMessage = e.message;
    } catch (e) {
      _errorMessage = 'Failed to load contributions.';
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