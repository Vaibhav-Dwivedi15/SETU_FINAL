import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/recovery_record.dart';
import '../models/recovery_record_codec.dart';
import '../models/report_status.dart';

/// Durable local storage for every recovery report (drafts included), one
/// JSON string per record in SharedPreferences -- the same approach as
/// the other SETU logs. Works with no connectivity at all.
///
/// Concurrency: every write is a read-modify-write of one shared list,
/// and several callers write at once (the report screens and the mesh
/// acknowledgement listener each hold their own store instance). Writes
/// are therefore serialized process-wide so one can never overwrite
/// another's update.
///
/// Forward compatibility: entries this build cannot decode (corrupt, or
/// written by a newer version) are kept verbatim across writes instead of
/// being dropped from storage.
class RecoveryReportStore {
  static const String _key = 'recovery_reports_v1';

  /// Bounds SharedPreferences growth on a long-lived device. Drafts and
  /// entries this build cannot read are never dropped by the cap; only
  /// the oldest decodable non-draft entries are.
  static const int maxEntries = 300;

  static Future<void>? _writeQueue;

  /// Tests run each case in its own async zone; a case that ends while a
  /// write is still pending would leave the shared queue waiting on a
  /// future that never completes. Clearing it lets the next case start a
  /// fresh chain in its own zone.
  @visibleForTesting
  static void resetForTesting() => _writeQueue = null;

  /// Runs [action] after every earlier write has finished. A failure in
  /// one action never blocks the ones queued behind it.
  static Future<T> _exclusive<T>(Future<T> Function() action) {
    // Created lazily so the first link belongs to the caller's zone.
    final result = (_writeQueue ?? Future<void>.value()).then((_) => action());
    _writeQueue = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<List<String>> _readRaw() async {
    final prefs = await SharedPreferences.getInstance();
    return List<String>.of(prefs.getStringList(_key) ?? const []);
  }

  Future<void> _writeRaw(List<String> raw) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, raw);
  }

  static Map<String, dynamic>? _tryDecodeMap(String raw) {
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  static RecoveryRecord? _tryDecodeRecord(String raw) {
    try {
      final map = _tryDecodeMap(raw);
      return map == null ? null : decodeRecoveryRecord(map);
    } catch (e) {
      // One unreadable entry must not hide the rest.
      developer.log('Skipping unreadable recovery record: $e', name: 'RecoveryReportStore');
      return null;
    }
  }

  /// Newest first. Entries this build cannot decode are omitted from the
  /// result but remain in storage.
  Future<List<RecoveryRecord>> all() async {
    final records = <RecoveryRecord>[];
    for (final raw in await _readRaw()) {
      final record = _tryDecodeRecord(raw);
      if (record != null) records.add(record);
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

  Future<void> upsert(RecoveryRecord record) => _exclusive(() async {
        final raw = await _readRaw();
        final encoded = jsonEncode(record.toJson());
        final index = raw.indexWhere((s) => _tryDecodeMap(s)?['id'] == record.id);
        if (index == -1) {
          raw.insert(0, encoded);
        } else {
          raw[index] = encoded;
        }
        await _writeRaw(_capped(raw));
      });

  Future<void> delete(String id) => _exclusive(() async {
        final raw = await _readRaw();
        raw.removeWhere((s) => _tryDecodeMap(s)?['id'] == id);
        await _writeRaw(raw);
      });

  /// Drops the oldest decodable non-draft entries beyond [maxEntries].
  /// "Oldest" is by last update, not list position (updates replace an
  /// entry in place).
  List<String> _capped(List<String> raw) {
    if (raw.length <= maxEntries) return raw;
    final decoded = {for (final entry in raw) entry: _tryDecodeRecord(entry)};
    final capped = decoded.entries
        .where((e) => e.value != null && e.value!.status != ReportStatus.draft)
        .toList()
      ..sort((a, b) => b.value!.updatedAt.compareTo(a.value!.updatedAt));
    final dropped = capped.skip(maxEntries).map((e) => e.key).toSet();
    return raw.where((entry) => !dropped.contains(entry)).toList();
  }
}
