import 'dart:math';

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
    if (!record.status.isEditable) {
      throw StateError('A ${record.status.label} report can no longer be edited.');
    }
    final saved = record.withMeta(status: ReportStatus.draft, updatedAt: _clock(), clearError: true);
    await _store.upsert(saved);
    return saved;
  }

  Future<void> deleteDraft(String id) async {
    final existing = await _store.byId(id);
    if (existing != null && existing.status == ReportStatus.draft) {
      await _store.delete(id);
    }
  }

  /// Validates, saves durably as pendingSync, then tries to dispatch.
  /// Returns the stored record: pendingSync if the dispatch was accepted,
  /// failed (still saved) if it was not. Throws
  /// [RecoveryValidationException] without saving anything if invalid.
  Future<RecoveryRecord> submit(RecoveryRecord record) async {
    final errors = record.validate();
    if (errors.isNotEmpty) throw RecoveryValidationException(errors);
    if (!record.status.isEditable) {
      throw StateError('A ${record.status.label} report cannot be submitted again.');
    }

    final pending = record.withMeta(
      status: ReportStatus.pendingSync,
      updatedAt: _clock(),
      clearError: true,
    );
    await _store.upsert(pending);
    return _dispatch(pending);
  }

  /// Re-attempts a failed report.
  Future<RecoveryRecord> retry(String id) async {
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
  }

  Future<RecoveryRecord> _dispatch(RecoveryRecord pending) async {
    try {
      final emergencyId = await _dispatcher.dispatch(pending);
      final queued = pending.withMeta(emergencyId: emergencyId, updatedAt: _clock());
      await _store.upsert(queued);
      return queued;
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
  Future<void> updateStatusByEmergencyId(String emergencyId, String newStatus) async {
    if (emergencyId.isEmpty || newStatus != 'Delivered') return;
    for (final record in await _store.all()) {
      if (record.emergencyId == emergencyId && record.status == ReportStatus.pendingSync) {
        await _store.upsert(
          record.withMeta(status: ReportStatus.submitted, updatedAt: _clock()),
        );
        return;
      }
    }
  }
}
