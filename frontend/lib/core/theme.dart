// lib/core/theme.dart
// Defines the visual identity of the entire app.
// All screens use these colors and text styles - never hardcode colors elsewhere.

import 'package:flutter/material.dart';

class AppTheme {
  // ─── Brand Colors ────────────────────────────────────────────────────────────
  static const Color primary = Color(0xFF1B5E20);       // Deep green - main brand color
  static const Color primaryLight = Color(0xFF4CAF50);  // Light green - accents
  static const Color primaryDark = Color(0xFF003300);   // Dark green - headers
  static const Color accent = Color(0xFF00BCD4);        // Cyan - highlights

  // ─── Background & Surface ───────────────────────────────────────────────────
  static const Color background = Color(0xFFF5F5F5);    // Light grey page background
  static const Color surface = Color(0xFFFFFFFF);       // White card background
  static const Color divider = Color(0xFFE0E0E0);       // Subtle dividers

  // ─── Text Colors ────────────────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFF212121);   // Main text
  static const Color textSecondary = Color(0xFF757575); // Subtitles, labels
  static const Color textOnPrimary = Color(0xFFFFFFFF); // Text on green backgrounds

  // ─── Semantic Colors ────────────────────────────────────────────────────────
  static const Color success = Color(0xFF4CAF50);       // Good financial state
  static const Color warning = Color(0xFFFF9800);       // At risk state
  static const Color error = Color(0xFFF44336);         // Critical / overspent
  static const Color info = Color(0xFF2196F3);          // Neutral info

  // ─── Score Category Colors ──────────────────────────────────────────────────
  // Used on dashboard score card and insights screen.
  static Color scoreColor(String category) {
    switch (category) {
      case 'Elite':
      case 'Excellent':
        return success;
      case 'Very Good':
      case 'Good':
        return primaryLight;
      case 'Average':
        return info;
      case 'At Risk':
        return warning;
      case 'Critical':
        return error;
      default:
        return textSecondary;
    }
  }

  // ─── Category Colors for Charts ─────────────────────────────────────────────
  // Used in pie chart to color each expense category slice.
  static const List<Color> categoryColors = [
    Color(0xFF4CAF50), // Food
    Color(0xFF2196F3), // Transport
    Color(0xFF9C27B0), // Entertainment
    Color(0xFFFF9800), // Shopping
    Color(0xFFF44336), // Health
    Color(0xFF00BCD4), // Education
    Color(0xFF795548), // Utilities
    Color(0xFF607D8B), // Rent
    Color(0xFF9E9E9E), // Other
  ];

  // ─── Material Theme ─────────────────────────────────────────────────────────
  static ThemeData get theme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        primary: primary,
        surface: surface,
        error: error,
      ),
      scaffoldBackgroundColor: background,

      // AppBar
      appBarTheme: const AppBarTheme(
        backgroundColor: primary,
        foregroundColor: textOnPrimary,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontFamily: 'Roboto',
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: textOnPrimary,
        ),
      ),

      // Cards
      cardTheme: CardThemeData(
        color: surface,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      ),

      // Elevated Buttons
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: textOnPrimary,
          minimumSize: const Size(double.infinity, 50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // Text Buttons
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
        ),
      ),

      // Input Fields
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
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
          borderSide: const BorderSide(color: primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: error),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        labelStyle: const TextStyle(color: textSecondary),
      ),

      // Bottom Navigation Bar
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: primary,
        unselectedItemColor: textSecondary,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),

      // Floating Action Button
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: textOnPrimary,
      ),
    );
  }
}