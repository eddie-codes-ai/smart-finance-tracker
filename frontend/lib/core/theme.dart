// lib/core/theme.dart
// UPDATED in Batch 9: added scoreColor() and categoryColor() static helpers
// used by dashboard, insights, and reports screens.

import 'package:flutter/material.dart';

class AppTheme {
  // ─── Brand Colors ─────────────────────────────────────────────────────────
  static const Color primary = Color(0xFF1B5E20);
  static const Color primaryLight = Color(0xFF4CAF50);
  static const Color accent = Color(0xFF00BCD4);

  // ─── Semantic Colors ──────────────────────────────────────────────────────
  static const Color success = Color(0xFF2E7D32);
  static const Color warning = Color(0xFFF57F17);
  static const Color error = Color(0xFFC62828);
  static const Color info = Color(0xFF01579B);

  // ─── Neutral Colors ───────────────────────────────────────────────────────
  static const Color background = Color(0xFFF5F6FA);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color divider = Color(0xFFE0E0E0);
  static const Color textPrimary = Color(0xFF1A1A2E);
  static const Color textSecondary = Color(0xFF6B7280);

  // ─── Score Category → Color ───────────────────────────────────────────────
  /// Returns the color matching a financial score category string.
  /// Used by score cards on Dashboard and Insights.
  static Color scoreColor(String category) {
    switch (category) {
      case 'Elite':
      case 'Excellent':
        return const Color(0xFF1B5E20);   // deep green
      case 'Very Good':
      case 'Good':
        return const Color(0xFF388E3C);   // medium green
      case 'Average':
        return const Color(0xFF01579B);   // info blue
      case 'At Risk':
        return const Color(0xFFF57F17);   // warning orange
      case 'Critical':
        return const Color(0xFFC62828);   // error red
      default:
        return const Color(0xFF6B7280);   // neutral grey
    }
  }

  // ─── Category Index → Color ───────────────────────────────────────────────
  /// Returns a distinct color for each expense category index.
  /// Used by the pie chart in reports_screen.dart.
  /// 9 colors for 9 expense categories — matches AppConstants.expenseCategories order.
  static Color categoryColor(int index) {
    const colors = [
      Color(0xFF1B5E20), // Food        — deep green
      Color(0xFF0288D1), // Transport   — blue
      Color(0xFF7B1FA2), // Entertainment — purple
      Color(0xFFE65100), // Shopping    — deep orange
      Color(0xFFC62828), // Health      — red
      Color(0xFF00695C), // Education   — teal
      Color(0xFFF57F17), // Utilities   — amber
      Color(0xFF4527A0), // Rent        — deep purple
      Color(0xFF546E7A), // Other       — blue grey
    ];
    return colors[index % colors.length];
  }

  // ─── Theme Data ───────────────────────────────────────────────────────────
  static ThemeData get theme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: background,

      // AppBar
      appBarTheme: const AppBarTheme(
        backgroundColor: surface,
        foregroundColor: textPrimary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
        iconTheme: IconThemeData(color: textPrimary),
      ),

      // Cards
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: divider, width: 0.5),
        ),
      ),

      // Elevated Button
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // Text Button
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),

      // Outlined Button
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: const BorderSide(color: primary),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),

      // Input fields
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: error),
        ),
        labelStyle:
            const TextStyle(color: textSecondary, fontSize: 14),
        hintStyle:
            const TextStyle(color: textSecondary, fontSize: 14),
      ),

      // Bottom Navigation
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: primary,
        unselectedItemColor: textSecondary,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
        selectedLabelStyle:
            TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        unselectedLabelStyle: TextStyle(fontSize: 11),
      ),

      // FAB
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 4,
      ),

      // Divider
      dividerTheme: const DividerThemeData(
        color: divider,
        thickness: 0.5,
        space: 0,
      ),
    );
  }
}