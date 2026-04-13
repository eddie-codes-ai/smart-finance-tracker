// lib/providers/theme_provider.dart
// Manages the app theme mode — light, dark, or system default.
// Persists the user's choice in shared_preferences so it survives
// app restarts. Loaded before the app renders in app.dart.

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider extends ChangeNotifier {
  static const String _key = 'theme_mode';

  ThemeMode _themeMode = ThemeMode.system;

  ThemeMode get themeMode => _themeMode;

  bool get isLight  => _themeMode == ThemeMode.light;
  bool get isDark   => _themeMode == ThemeMode.dark;
  bool get isSystem => _themeMode == ThemeMode.system;

  /// Load the saved theme preference on app start.
  Future<void> loadTheme() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_key);
      switch (saved) {
        case 'light':
          _themeMode = ThemeMode.light;
          break;
        case 'dark':
          _themeMode = ThemeMode.dark;
          break;
        default:
          _themeMode = ThemeMode.system;
      }
      notifyListeners();
    } catch (_) {
      // Keep default (system) if prefs unavailable
    }
  }

  /// Set and persist a new theme mode.
  Future<void> setTheme(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      String value;
      switch (mode) {
        case ThemeMode.light:
          value = 'light';
          break;
        case ThemeMode.dark:
          value = 'dark';
          break;
        default:
          value = 'system';
      }
      await prefs.setString(_key, value);
    } catch (_) {}
  }
}