// lib/core/helb_storage.dart
//
// HelbPlan — data model for a semester budget plan.
// HelbStorage — static async helpers to save/load/clear from SharedPreferences.
//
// The plan is stored as a single JSON string under 'helb_plan'.
// All computed time-based values (days elapsed, remaining balance pace)
// are lazy getters on HelbPlan so they're always current without re-saving.

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

// ── Category groupings for the 50/30/20 preset ────────────────────────────
const List<String> kHelbNeedsCategories = [
  'Food', 'Transport', 'Health', 'Education', 'Utilities', 'Rent',
];
const List<String> kHelbWantsCategories = [
  'Entertainment', 'Shopping', 'Other',
];

const String _kHelbPlanKey = 'helb_plan';

// ─────────────────────────────────────────────────────────────────────────────
// HelbPlan
// ─────────────────────────────────────────────────────────────────────────────

class HelbPlan {
  final String semesterName;
  final double helbAmount;
  final DateTime startDate;
  final DateTime endDate;

  /// category → allocated amount (KES).
  /// Categories not present in this map have no allocation.
  final Map<String, double> allocations;

  const HelbPlan({
    required this.semesterName,
    required this.helbAmount,
    required this.startDate,
    required this.endDate,
    required this.allocations,
  });

  // ── Time getters ──────────────────────────────────────────────────────────

  /// Total days in the semester (minimum 1 to avoid division by zero).
  int get totalDays => endDate.difference(startDate).inDays.clamp(1, 9999);

  /// Days that have elapsed since semester start, clamped to [0, totalDays].
  int get daysElapsed {
    final now = DateTime.now();
    if (now.isBefore(startDate)) return 0;
    if (now.isAfter(endDate)) return totalDays;
    return now.difference(startDate).inDays.clamp(0, totalDays);
  }

  /// Days still remaining until semester end, clamped to [0, totalDays].
  int get daysRemaining => (totalDays - daysElapsed).clamp(0, totalDays);

  /// Fraction of the semester that has elapsed (0.0 – 1.0).
  double get progressFraction => daysElapsed / totalDays;

  // ── Budget getters ────────────────────────────────────────────────────────

  /// How much should have been spent by today, based on linear burn.
  double get expectedSpentByNow => helbAmount * progressFraction;

  /// Sum of all category allocations.
  double get allocationsTotal =>
      allocations.values.fold(0.0, (acc, v) => acc + v);

  // ── Serialisation ─────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
        'semesterName': semesterName,
        'helbAmount': helbAmount,
        'startDate': startDate.toIso8601String(),
        'endDate': endDate.toIso8601String(),
        'allocations': allocations,
      };

  factory HelbPlan.fromJson(Map<String, dynamic> json) => HelbPlan(
        semesterName: json['semesterName'] as String,
        helbAmount: (json['helbAmount'] as num).toDouble(),
        startDate: DateTime.parse(json['startDate'] as String),
        endDate: DateTime.parse(json['endDate'] as String),
        allocations: (json['allocations'] as Map<String, dynamic>).map(
          (k, v) => MapEntry(k, (v as num).toDouble()),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// HelbStorage
// ─────────────────────────────────────────────────────────────────────────────

class HelbStorage {
  /// Persist the plan to SharedPreferences.
  static Future<void> savePlan(HelbPlan plan) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kHelbPlanKey, jsonEncode(plan.toJson()));
  }

  /// Load the plan from SharedPreferences, or null if none is saved.
  static Future<HelbPlan?> loadPlan() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kHelbPlanKey);
    if (raw == null) return null;
    try {
      return HelbPlan.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      // Corrupted data — clear it silently.
      await prefs.remove(_kHelbPlanKey);
      return null;
    }
  }

  /// Remove the plan from SharedPreferences.
  static Future<void> clearPlan() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kHelbPlanKey);
  }

  /// Returns true if a plan has been saved.
  static Future<bool> hasPlan() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_kHelbPlanKey);
  }
}