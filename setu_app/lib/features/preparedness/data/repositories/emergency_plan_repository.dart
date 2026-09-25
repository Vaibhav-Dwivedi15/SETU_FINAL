import 'dart:convert';
import 'dart:developer' as developer;

import 'package:shared_preferences/shared_preferences.dart';

import '../models/emergency_plan.dart';

/// Local-only storage for the family emergency plan (same
/// SharedPreferences approach as the saved emergency contacts).
class EmergencyPlanRepository {
  static const String _key = 'emergency_plan';

  Future<EmergencyPlan> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return EmergencyPlan.empty;
    try {
      return EmergencyPlan.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (e) {
      developer.log('Unreadable emergency plan, treating as empty: $e',
          name: 'EmergencyPlanRepository');
      return EmergencyPlan.empty;
    }
  }

  Future<void> save(EmergencyPlan plan) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(plan.toJson()));
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
