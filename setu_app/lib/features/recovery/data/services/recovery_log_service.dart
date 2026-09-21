import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/recovery_report_model.dart';

/// SharedPreferences-backed list, most-recent-first, capped -- same
/// pattern as RelayLogService (see that file's own comment for why the
/// cap exists: a long-lived device's local log must not grow
/// SharedPreferences unboundedly).
class RecoveryLogService {
  static const String _key = 'recovery_report_log';
  static const int _maxEntries = 300;

  Future<List<RecoveryReportModel>> getLog() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getStringList(_key) ?? [];
    return data
        .map((item) => RecoveryReportModel.fromJson(jsonDecode(item)))
        .toList();
  }

  Future<void> _saveLog(List<RecoveryReportModel> log) async {
    final prefs = await SharedPreferences.getInstance();
    final data = log.map((item) => jsonEncode(item.toJson())).toList();
    await prefs.setStringList(_key, data);
  }

  Future<void> addEntry(RecoveryReportModel entry) async {
    final log = await getLog();
    log.insert(0, entry);
    if (log.length > _maxEntries) {
      log.removeRange(_maxEntries, log.length);
    }
    await _saveLog(log);
  }

  /// Mirrors HistoryService.updateStatusByEmergencyId exactly -- finds
  /// by emergencyId (not list position), since the ack can arrive well
  /// after this entry was written and other entries may have been
  /// added in between. No-op (not an error) if no matching entry is
  /// found, e.g. the log was cleared, or the ack is for a report this
  /// device didn't originate (shouldn't normally reach here, but the
  /// listener doesn't pre-filter).
  Future<void> updateStatusByEmergencyId(String emergencyId, String newStatus) async {
    if (emergencyId.isEmpty) return;

    final log = await getLog();
    final index = log.indexWhere((r) => r.emergencyId == emergencyId);
    if (index == -1) return;

    log[index] = log[index].copyWith(status: newStatus);
    await _saveLog(log);
  }

  Future<void> clearLog() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
