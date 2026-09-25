import 'dart:convert';
import 'dart:developer' as developer;

import 'package:shared_preferences/shared_preferences.dart';

import '../models/recovery_record.dart';
import '../models/recovery_record_codec.dart';
import '../models/report_status.dart';

/// Durable local storage for every recovery report (drafts included), one
/// JSON string per record in SharedPreferences -- the same approach as
/// the other SETU logs. Works with no connectivity at all.
class RecoveryReportStore {
  static const String _key = 'recovery_reports_v1';

  /// Bounds SharedPreferences growth on a long-lived device. Drafts are
  /// never dropped by the cap; only the oldest non-draft entries are.
  static const int maxEntries = 300;

  /// Newest first.
  Future<List<RecoveryRecord>> all() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? const [];
    final records = <RecoveryRecord>[];
    for (final item in raw) {
      try {
        final record = decodeRecoveryRecord(jsonDecode(item) as Map<String, dynamic>);
        if (record != null) records.add(record);
      } catch (e) {
        // One unreadable entry must not hide the rest.
        developer.log('Skipping unreadable recovery record: $e', name: 'RecoveryReportStore');
      }
    }
    records.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return records;
  }

  Future<RecoveryRecord?> byId(String id) async {
    for (final r in await all()) {
      if (r.id == id) return r;
    }
    return null;
  }

  Future<void> upsert(RecoveryRecord record) async {
    final records = await all();
    final index = records.indexWhere((r) => r.id == record.id);
    if (index == -1) {
      records.insert(0, record);
    } else {
      records[index] = record;
    }
    await _write(_capped(records));
  }

  Future<void> delete(String id) async {
    final records = await all();
    records.removeWhere((r) => r.id == id);
    await _write(records);
  }

  List<RecoveryRecord> _capped(List<RecoveryRecord> records) {
    if (records.length <= maxEntries) return records;
    final kept = <RecoveryRecord>[];
    var budget = maxEntries;
    // records is newest-first: keep every draft, fill the rest newest-first.
    for (final r in records) {
      if (r.status == ReportStatus.draft) {
        kept.add(r);
      } else if (budget > 0) {
        kept.add(r);
        budget--;
      }
    }
    return kept;
  }

  Future<void> _write(List<RecoveryRecord> records) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        _key, records.map((r) => jsonEncode(r.toJson())).toList());
  }
}
