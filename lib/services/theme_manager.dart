import 'package:cravy/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeManager with ChangeNotifier {
  final String _key = "themeIndex";
  late int _themeIndex;

  ThemeManager() {
    _themeIndex = 0; // Default to the first theme
    _loadTheme();
  }

  ThemeData get currentTheme => AppThemes.themes[_themeIndex];

  int get themeIndex => _themeIndex;

  void _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    _themeIndex = prefs.getInt(_key) ?? 0;
    notifyListeners();
  }

  void setTheme(int themeIndex) async {
    if (_themeIndex == themeIndex) return;

    _themeIndex = themeIndex;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key, themeIndex);
    notifyListeners();
  }
}