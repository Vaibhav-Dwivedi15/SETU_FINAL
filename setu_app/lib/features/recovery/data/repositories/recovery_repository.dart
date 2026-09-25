import 'dart:math';

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../models/damage_report.dart';
import '../models/missing_person_report.dart';
import '../models/recovery_record.dart';
import '../models/recovery_report_type.dart';
import '../models/report_status.dart';
import '../models/resource_request.dart';
import '../services/recovery_dispatcher.dart';
import '../services/recovery_report_store.dart';

class RecoveryValidationException implements Exception {
  const RecoveryValidationException(this.errors);
  final Map<String, String> errors;

  @override
  String toString() => errors.values.join(' ');
}

/// Owns the recovery report lifecycle:
///
///   draft --submit--> pendingSync --ack--> submitted
///                          \--dispatch error--> failed --retry--> ...
///
/// Every transition is persisted before anything is attempted over the
/// network, so a report is never lost to a crash, a denied permission or
/// having no connectivity. `submitted` is set only by a real
/// acknowledgement (see [updateStatusByEmergencyId]); it never means an
/// authority has reviewed the report.
///
/// Every change to one report (save, submit, retry, delete, acknowledge)
/// runs one at a time per report id, and each checks the STORED status,
/// not the caller's copy. That is what stops a stale form from resetting
/// a queued report to draft, a double tap from sending two packets, and
/// an acknowledgement from being lost to a concurrent save.
class RecoveryRepository {
  RecoveryRepository({
    RecoveryReportStore? store,
    RecoveryDispatcher? dispatcher,
    DateTime Function()? clock,
  })  : _store = store ?? RecoveryReportStore(),
        _dispatcherOverride = dispatcher,
        _clock = clock ?? DateTime.now;

  final RecoveryReportStore _store;
  final RecoveryDispatcher? _dispatcherOverride;
  final DateTime Function() _clock;

  /// Created lazily so constructing a repository (e.g. inside the mesh
  /// ack listener at app start) never touches permissions or location.
  late final RecoveryDispatcher _dispatcher =
      _dispatcherOverride ?? MeshRecoveryDispatcher();

  static final Random _random = Random.secure();

  /// Tail of the serialized work queue per report id. Static because the
  /// screens and the mesh acknowledgement listener each create their own
  /// repository instance.
  static final Map<String, Future<void>> _perIdQueue = {};

  /// See [RecoveryReportStore.resetForTesting].
  @visibleForTesting
  static void resetForTesting() {
    _perIdQueue.clear();
    RecoveryReportStore.resetForTesting();
  }

  static Future<T> _serialized<T>(String id, Future<T> Function() action) {
    final previous = _perIdQueue[id] ?? Future.value();
    final result = previous.then((_) => action());
    final tail = result.then<void>((_) {}, onError: (Object _) {});
    _perIdQueue[id] = tail;
    // Forget finished ids so the map does not grow with every report.
    tail.whenComplete(() {
      if (identical(_perIdQueue[id], tail)) _perIdQueue.remove(id);
    });
    return result;
  }

  /// The status that actually governs [record]: what is stored, falling
  /// back to the caller's copy for a report that has never been saved.
  Future<ReportStatus> _effectiveStatus(RecoveryRecord record) async =>
      (await _store.byId(record.id))?.status ?? record.status;

  String newId(RecoveryReportType type) {
    const prefixes = {
      RecoveryReportType.damage: 'DMG',
      RecoveryReportType.missingPerson: 'MIS',
      RecoveryReportType.resourceRequest: 'REQ',
    };
    const alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
    final suffix = List.generate(6, (_) => alphabet[_random.nextInt(alphabet.length)]).join();
    return '${prefixes[type]}-$suffix';
  }

  /// A blank, unsaved draft of [type].
  RecoveryRecord newDraft(RecoveryReportType type) {
    final now = _clock();
    final id = newId(type);
    switch (type) {
      case RecoveryReportType.damage:
        return DamageReport(id: id, status: ReportStatus.draft, createdAt: now, updatedAt: now);
      case RecoveryReportType.missingPerson:
        return MissingPersonReport(id: id, status: ReportStatus.draft, createdAt: now, updatedAt: now);
      case RecoveryReportType.resourceRequest:
        return ResourceRequest(id: id, status: ReportStatus.draft, createdAt: now, updatedAt: now);
    }
  }

  Future<List<RecoveryRecord>> list({RecoveryReportType? type}) async =>
      filter(await _store.all(), type);

  /// Pure filter, exposed so history filtering is testable without storage.
  static List<RecoveryRecord> filter(List<RecoveryRecord> records, RecoveryReportType? type) =>
      type == null ? records : records.where((r) => r.type == type).toList();

  Future<RecoveryRecord?> get(String id) => _store.byId(id);

  /// Saves partial content as a draft. Drafts need no validation, but an
  /// entirely blank form is not worth saving.
  Future<RecoveryRecord> saveDraft(RecoveryRecord record) async {
    if (record.isBlank) {
      throw const RecoveryValidationException({'form': 'Nothing to save yet.'});
    }
    return _serialized(record.id, () async {
      final status = await _effectiveStatus(record);
      if (!status.isEditable) {
        throw StateError('A ${status.label} report can no longer be edited.');
      }
      final saved = record.withMeta(status: ReportStatus.draft, updatedAt: _clock(), clearError: true);
      await _store.upsert(saved);
      return saved;
    });
  }

  Future<void> deleteDraft(String id) => _serialized(id, () async {
        final existing = await _store.byId(id);
        if (existing != null && existing.status == ReportStatus.draft) {
          await _store.delete(id);
        }
      });

  /// Validates, saves durably as pendingSync, then tries to dispatch.
  /// Returns the stored record: pendingSync if the dispatch was accepted,
  /// failed (still saved) if it was not. Throws
  /// [RecoveryValidationException] without saving anything if invalid.
  ///
  /// Submitting a report that is already queued or acknowledged (a double
  /// tap, or a stale copy of the form) throws [StateError] and sends
  /// nothing.
  Future<RecoveryRecord> submit(RecoveryRecord record) async {
    final errors = record.validate();
    if (errors.isNotEmpty) throw RecoveryValidationException(errors);

    return _serialized(record.id, () async {
      final status = await _effectiveStatus(record);
      if (!status.isEditable) {
        throw StateError('A ${status.label} report cannot be submitted again.');
      }
      final pending = record.withMeta(
        status: ReportStatus.pendingSync,
        updatedAt: _clock(),
        clearError: true,
      );
      await _store.upsert(pending);
      return _dispatch(pending);
    });
  }

  /// Re-attempts a failed report.
  Future<RecoveryRecord> retry(String id) => _serialized(id, () async {
        final record = await _store.byId(id);
        if (record == null) throw StateError('Report $id not found.');
        if (!record.status.canRetry) {
          throw StateError('Only a failed report can be retried.');
        }
        final pending = record.withMeta(
          status: ReportStatus.pendingSync,
          updatedAt: _clock(),
          clearError: true,
        );
        await _store.upsert(pending);
        return _dispatch(pending);
      });

  Future<RecoveryRecord> _dispatch(RecoveryRecord pending) async {
    var current = pending;
    try {
      // The emergencyId is stored as soon as the packet exists, before it
      // is handed to the transport, so an acknowledgement (or a crash
      // right after the hand-off) can never find a report without it.
      final emergencyId = await _dispatcher.dispatch(
        pending,
        onPacketBuilt: (id) async {
          current = pending.withMeta(emergencyId: id, updatedAt: _clock());
          await _store.upsert(current);
        },
      );
      if (current.emergencyId != emergencyId) {
        current = pending.withMeta(emergencyId: emergencyId, updatedAt: _clock());
      }
      await _store.upsert(current);
      return current;
    } catch (e) {
      final failed = pending.withMeta(
        status: ReportStatus.failed,
        updatedAt: _clock(),
        lastError: e.toString().replaceFirst('Exception: ', ''),
      );
      await _store.upsert(failed);
      return failed;
    }
  }

  /// Acknowledgement hook. MeshLocator's existing ack listener calls this
  /// with 'Delivered' for every acknowledgement it sees; only a report
  /// that is pending sync and carries the matching emergencyId moves to
  /// submitted. Unknown ids and other states are ignored.
  ///
  /// What an acknowledgement is: the mesh originates one only after a
  /// node's upload of the packet was accepted by the backend ingest
  /// (MeshServiceImpl._markPacketDelivered), and it reaches this device
  /// over the mesh. It is therefore a receipt, not a review: nothing here
  /// means an authority has seen, acted on or resolved the report.
  Future<void> updateStatusByEmergencyId(String emergencyId, String newStatus) async {
    if (emergencyId.isEmpty || newStatus != 'Delivered') return;
    final match = (await _store.all()).where((r) => r.emergencyId == emergencyId).firstOrNull;
    if (match == null) return;
    await _serialized(match.id, () async {
      // Re-read under the per-report lock: the record may have moved on
      // (e.g. been retried) while this call was waiting.
      final current = await _store.byId(match.id);
      if (current != null &&
          current.emergencyId == emergencyId &&
          current.status == ReportStatus.pendingSync) {
        await _store.upsert(current.withMeta(status: ReportStatus.submitted, updatedAt: _clock()));
      }
    });
  }
}
