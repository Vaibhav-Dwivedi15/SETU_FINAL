// =====================================================
// SETU Project
// Module : Child Safety Mode (UI + local storage only)
// Owner  : Sudheer
// =====================================================

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/child_profile_model.dart';

class ChildSafetyService {
  static const String _storageKey = 'child_safety_profiles';

  Future<List<ChildProfileModel>> getProfiles() async {
    final prefs = await SharedPreferences.getInstance();

    final jsonString = prefs.getString(_storageKey);

    if (jsonString == null || jsonString.isEmpty) {
      return [];
    }

    final List<dynamic> decoded = jsonDecode(jsonString);

    return decoded
        .map((e) => ChildProfileModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveProfiles(List<ChildProfileModel> profiles) async {
    final prefs = await SharedPreferences.getInstance();

    final jsonString = jsonEncode(profiles.map((e) => e.toJson()).toList());

    await prefs.setString(_storageKey, jsonString);
  }
}
