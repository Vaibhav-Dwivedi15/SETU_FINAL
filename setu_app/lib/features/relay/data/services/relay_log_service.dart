import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/relay_log_entry.dart';

/// Aug 6 2026. Same pattern as HistoryService (SharedPreferences-backed
/// list, most-recent-first). Capped at 500 entries -- a device that's
/// been relaying for weeks shouldn't grow this list unboundedly in
/// SharedPreferences; oldest entries are dropped once the cap is hit.
class RelayLogService {
  static const String _key = "relay_log";
  static const int _maxEntries = 500;

  Future<List<RelayLogEntry>> getLog() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getStringList(_key) ?? [];
    return data.map((item) => RelayLogEntry.fromJson(jsonDecode(item))).toList();
  }

  Future<void> _saveLog(List<RelayLogEntry> log) async {
    final prefs = await SharedPreferences.getInstance();
    final data = log.map((item) => jsonEncode(item.toJson())).toList();
    await prefs.setStringList(_key, data);
  }

  Future<void> addEntry(RelayLogEntry entry) async {
    final log = await getLog();
    log.insert(0, entry);
    if (log.length > _maxEntries) {
      log.removeRange(_maxEntries, log.length);
    }
    await _saveLog(log);
  }

  Future<void> clearLog() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
