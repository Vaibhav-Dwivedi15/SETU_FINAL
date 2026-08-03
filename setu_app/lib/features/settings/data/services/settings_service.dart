import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/settings_model.dart';

class SettingsService {
  static const String _settingsKey = "setu_settings";

  Future<SettingsModel> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();

    final jsonString = prefs.getString(_settingsKey);

    if (jsonString == null) {
      return SettingsModel.defaultSettings();
    }

    final json = jsonDecode(jsonString);

    return SettingsModel.fromJson(json);
  }

  Future<void> saveSettings(SettingsModel settings) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(_settingsKey, jsonEncode(settings.toJson()));
  }

  Future<void> resetSettings() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.remove(_settingsKey);
  }
}
