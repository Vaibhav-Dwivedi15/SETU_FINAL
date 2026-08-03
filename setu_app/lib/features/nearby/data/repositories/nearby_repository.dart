import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/nearby_alert_model.dart';

class NearbyRepository {
  static const String _storageKey = "nearby_alerts";

  Future<void> addAlert(NearbyAlertModel alert) async {
    final prefs = await SharedPreferences.getInstance();

    final alerts = await getAlerts();

    alerts.insert(0, alert);

    final jsonList = alerts.map((e) => jsonEncode(e.toJson())).toList();

    await prefs.setStringList(_storageKey, jsonList);
  }

  Future<List<NearbyAlertModel>> getAlerts() async {
    final prefs = await SharedPreferences.getInstance();

    final jsonList = prefs.getStringList(_storageKey) ?? [];

    return jsonList
        .map((e) => NearbyAlertModel.fromJson(jsonDecode(e)))
        .toList();
  }

  Future<void> clearAlerts() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.remove(_storageKey);
  }
}
