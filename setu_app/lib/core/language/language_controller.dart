// =====================================================
// SETU Project
// Module : Language Controller
// =====================================================
//
// Mirrors core/theme/theme_controller.dart's exact pattern (same
// reasoning: no state-management package in pubspec, one ChangeNotifier
// + ListenableBuilder is enough for one piece of app-wide state).
//
// SCOPE, HONESTLY: language_selection_screen.dart's own header comment
// already flagged that its choice was saved but not applied app-wide.
// This controller is the missing piece — combined with
// core/l10n/app_strings.dart, it makes AppStrings.of(context).xyz
// re-render in the selected language everywhere that's been wired up.
//
// "Wired up everywhere" is NOT a claim this first pass makes. Retrofitting
// every hardcoded string in every existing screen is a large, separate
// mechanical pass. This delivers the INFRASTRUCTURE plus a handful of
// key screens as a working example (see app_strings.dart for exactly
// which keys exist) — the same honest, incremental approach the
// project's language screen already modeled.

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LanguageController extends ChangeNotifier {
  LanguageController._internal();

  static final LanguageController instance = LanguageController._internal();

  static const String _prefsKey = 'app_language_code';
  static const String defaultCode = 'en';

  String _languageCode = defaultCode;
  String get languageCode => _languageCode;

  Future<void> loadSavedLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    _languageCode = prefs.getString(_prefsKey) ?? defaultCode;
    notifyListeners();
  }

  Future<void> setLanguage(String code) async {
    _languageCode = code;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, code);
  }
}
