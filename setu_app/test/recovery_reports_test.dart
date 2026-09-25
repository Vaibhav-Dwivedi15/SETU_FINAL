// =====================================================
// SETU Project
// Module : Recovery reports (models, store, lifecycle) tests
// =====================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:setu_app/features/recovery/data/models/damage_report.dart';
import 'package:setu_app/features/recovery/data/models/missing_person_report.dart';
import 'package:setu_app/features/recovery/data/models/recovery_enums.dart';
import 'package:setu_app/features/recovery/data/models/recovery_record.dart';
import 'package:setu_app/features/recovery/data/models/recovery_report_type.dart';
import 'package:setu_app/features/recovery/data/models/report_status.dart';
import 'package:setu_app/features/recovery/data/models/resource_request.dart';
import 'package:setu_app/features/recovery/data/repositories/recovery_repository.dart';
import 'package:setu_app/features/recovery/data/services/recovery_dispatcher.dart';
import 'package:setu_app/features/recovery/data/services/recovery_report_store.dart';
import 'package:setu_app/mesh/enums/emergency_priority.dart';

class FakeDispatcher implements RecoveryDispatcher {
  FakeDispatcher({this.error});

  Object? error;
  final dispatched = <RecoveryRecord>[];

  @override
  Future<String> dispatch(RecoveryRecord record) async {
    dispatched.add(record);
    if (error != null) throw error!;
    return 'emergency-${dispatched.length}';
  }
}

final _t0 = DateTime.utc(2026, 9, 1, 10);

DamageReport validDamage(RecoveryRepository repo) => (repo.newDraft(RecoveryReportType.damage)
        as DamageReport)
    .copyWith(
  category: DamageCategory.road,
  severity: DamageSeverity.high,
  location: 'NH-44 near the bridge',
  description: 'Road washed away, vehicles cannot pass.',
);

MissingPersonReport validMissing(RecoveryRepository repo) =>
    (repo.newDraft(RecoveryReportType.missingPerson) as MissingPersonReport).copyWith(
      name: 'Ramesh Kumar',
      approximateAge: 34,
      location: 'Relief camp gate',
      description: 'Tall, blue jacket, limps slightly.',
    );

ResourceRequest validRequest(RecoveryRepository repo) =>
    (repo.newDraft(RecoveryReportType.resourceRequest) as ResourceRequest).copyWith(
      resourceType: ResourceType.water,
      urgency: RequestUrgency.urgent,
      location: 'Ward 7 school',
      description: 'Forty people, no drinking water since morning.',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeDispatcher dispatcher;
  late RecoveryRepository repo;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    dispatcher = FakeDispatcher();
    repo = RecoveryRepository(dispatcher: dispatcher);
  });

  group('Damage report validation', () {
    test('a blank draft reports every required field', () {
      final errors = repo.newDraft(RecoveryReportType.damage).validate();
      expect(errors.keys, containsAll(['category', 'severity', 'location', 'description']));
    });

    test('short location/description are rejected, valid report passes', () {
      final bad = validDamage(repo).copyWith(location: 'ab', description: 'too short');
      expect(bad.validate().keys, containsAll(['location', 'description']));
      expect(validDamage(repo).validate(), isEmpty);
    });

    test('offers every category and severity required', () {
      expect(DamageCategory.values.map((c) => c.label),
          ['Building', 'Road', 'Electricity', 'Water', 'Fire', 'Other']);
      expect(DamageSeverity.values.map((s) => s.label), ['Low', 'Medium', 'High', 'Critical']);
    });
  });

  group('Missing person validation', () {
    test('requires name, age in 0-120, location and description', () {
      expect(repo.newDraft(RecoveryReportType.missingPerson).validate().keys,
          containsAll(['name', 'age', 'location', 'description']));
      expect(validMissing(repo).validate(), isEmpty);
      expect(validMissing(repo).copyWith(approximateAge: 150).validate().keys, ['age']);
    });

    test('identifying information is optional', () {
      expect(validMissing(repo).identifyingInfo, isEmpty);
      expect(validMissing(repo).validate(), isEmpty);
    });
  });

  group('Resource request validation', () {
    test('requires type, urgency, location, description', () {
      expect(repo.newDraft(RecoveryReportType.resourceRequest).validate().keys,
          containsAll(['resourceType', 'urgency', 'location', 'description']));
      expect(validRequest(repo).validate(), isEmpty);
    });

    test('offers every request type and urgency required', () {
      expect(ResourceType.values.map((t) => t.label),
          ['Food', 'Water', 'Medical assistance', 'Shelter', 'Rescue', 'Other']);
      expect(RequestUrgency.values.map((u) => u.label), ['Normal', 'Urgent', 'Critical']);
    });
  });

  group('Persistence', () {
    test('every report kind survives a JSON round trip through a new store', () async {
      final damage = await repo.saveDraft(validDamage(repo));
      final missing = await repo.saveDraft(validMissing(repo));
      final request = await repo.saveDraft(validRequest(repo));

      final reopened = RecoveryRepository(store: RecoveryReportStore(), dispatcher: dispatcher);
      final all = await reopened.list();
      expect(all.map((r) => r.id).toSet(), {damage.id, missing.id, request.id});

      final d = (await reopened.get(damage.id)) as DamageReport;
      expect(d.category, DamageCategory.road);
      expect(d.severity, DamageSeverity.high);
      expect(d.description, contains('washed away'));
      final m = (await reopened.get(missing.id)) as MissingPersonReport;
      expect(m.approximateAge, 34);
      final r = (await reopened.get(request.id)) as ResourceRequest;
      expect(r.urgency, RequestUrgency.urgent);
    });

    test('ids are prefixed by kind and unique', () {
      final ids = {
        for (var i = 0; i < 50; i++) repo.newId(RecoveryReportType.damage),
      };
      expect(ids, hasLength(50));
      expect(ids.every((id) => id.startsWith('DMG-')), isTrue);
      expect(repo.newId(RecoveryReportType.missingPerson), startsWith('MIS-'));
      expect(repo.newId(RecoveryReportType.resourceRequest), startsWith('REQ-'));
    });

    test('an unreadable stored entry does not hide the others', () async {
      final saved = await repo.saveDraft(validDamage(repo));
      final prefs = await SharedPreferences.getInstance();
      prefs.setStringList('recovery_reports_v1', [
        '{not json',
        '{"type":"unknown_kind","id":"x"}',
        ...prefs.getStringList('recovery_reports_v1')!,
      ]);
      expect((await repo.list()).map((r) => r.id), [saved.id]);
    });

    test('the size cap drops old non-drafts but never a draft', () async {
      final store = RecoveryReportStore();
      final draft = validDamage(repo).withMeta(updatedAt: _t0);
      await store.upsert(draft);
      for (var i = 0; i < RecoveryReportStore.maxEntries + 5; i++) {
        await store.upsert(validRequest(repo).withMeta(
          status: ReportStatus.pendingSync,
          updatedAt: _t0.add(Duration(minutes: i + 1)),
        ));
      }
      final all = await store.all();
      expect(all.where((r) => r.status == ReportStatus.draft), hasLength(1));
      expect(all.length, RecoveryReportStore.maxEntries + 1);
    });
  });

  group('Drafts', () {
    test('a draft is saved without validation and restored for editing', () async {
      final partial = (repo.newDraft(RecoveryReportType.damage) as DamageReport)
          .copyWith(category: DamageCategory.fire);
      final saved = await repo.saveDraft(partial);
      expect(saved.status, ReportStatus.draft);
      expect(dispatcher.dispatched, isEmpty, reason: 'a draft is never sent');

      final restored = (await repo.get(saved.id)) as DamageReport;
      expect(restored.category, DamageCategory.fire);
      expect(restored.severity, isNull);

      final edited = restored.copyWith(severity: DamageSeverity.low);
      await repo.saveDraft(edited);
      expect(await repo.list(), hasLength(1), reason: 'editing updates, not duplicates');
      expect(((await repo.get(saved.id)) as DamageReport).severity, DamageSeverity.low);
    });

    test('a completely blank form is not saved', () async {
      expect(() => repo.saveDraft(repo.newDraft(RecoveryReportType.damage)),
          throwsA(isA<RecoveryValidationException>()));
      expect(await repo.list(), isEmpty);
    });

    test('a draft can be deleted; a submitted report cannot', () async {
      final draft = await repo.saveDraft(validDamage(repo));
      await repo.deleteDraft(draft.id);
      expect(await repo.get(draft.id), isNull);

      final sent = await repo.submit(validDamage(repo));
      await repo.deleteDraft(sent.id);
      expect(await repo.get(sent.id), isNotNull);
    });

    test('a queued report can no longer be edited or re-submitted', () async {
      final sent = await repo.submit(validDamage(repo));
      expect(() => repo.saveDraft(sent), throwsStateError);
      expect(() => repo.submit(sent), throwsStateError);
    });
  });

  group('Status handling (honest states)', () {
    test('submitting an invalid report saves and sends nothing', () async {
      await expectLater(repo.submit(repo.newDraft(RecoveryReportType.damage)),
          throwsA(isA<RecoveryValidationException>()));
      expect(await repo.list(), isEmpty);
      expect(dispatcher.dispatched, isEmpty);
    });

    test('an accepted dispatch is PENDING SYNC, never submitted', () async {
      final result = await repo.submit(validDamage(repo));
      expect(result.status, ReportStatus.pendingSync);
      expect(result.emergencyId, 'emergency-1');
      expect(result.lastError, isNull);
      expect((await repo.get(result.id))!.status, ReportStatus.pendingSync);
    });

    test('the dispatched copy is already durably saved before sending', () async {
      final store = RecoveryReportStore();
      final seenDuringDispatch = <ReportStatus?>[];
      final probing = _ProbingDispatcher((record) async {
        seenDuringDispatch.add((await store.byId(record.id))?.status);
        return 'e1';
      });
      await RecoveryRepository(store: store, dispatcher: probing).submit(validDamage(repo));
      expect(seenDuringDispatch, [ReportStatus.pendingSync]);
    });

    test('a dispatch failure is FAILED but the report stays saved', () async {
      dispatcher.error = const RecoveryDispatchException('Bluetooth permission missing');
      final result = await repo.submit(validMissing(repo));
      expect(result.status, ReportStatus.failed);
      expect(result.lastError, 'Bluetooth permission missing');
      final stored = await repo.get(result.id);
      expect(stored, isNotNull);
      expect(stored!.status.description, 'Sync failed. Report remains saved locally.');
    });

    test('a failed report can be retried and then becomes pending sync', () async {
      dispatcher.error = Exception('no route');
      final failed = await repo.submit(validRequest(repo));
      expect(failed.status, ReportStatus.failed);

      dispatcher.error = null;
      final retried = await repo.retry(failed.id);
      expect(retried.status, ReportStatus.pendingSync);
      expect(retried.lastError, isNull);
      expect(dispatcher.dispatched, hasLength(2));
    });

    test('only failed reports can be retried', () async {
      final pending = await repo.submit(validDamage(repo));
      expect(() => repo.retry(pending.id), throwsStateError);
      expect(() => repo.retry('missing-id'), throwsStateError);
    });

    test('an acknowledgement moves PENDING SYNC to SUBMITTED, matched by emergencyId',
        () async {
      final a = await repo.submit(validDamage(repo));
      final b = await repo.submit(validRequest(repo));

      await repo.updateStatusByEmergencyId(a.emergencyId!, 'Delivered');
      expect((await repo.get(a.id))!.status, ReportStatus.submitted);
      expect((await repo.get(b.id))!.status, ReportStatus.pendingSync);
    });

    test('unknown ids, empty ids and non-ack statuses change nothing', () async {
      final a = await repo.submit(validDamage(repo));
      await repo.updateStatusByEmergencyId('nope', 'Delivered');
      await repo.updateStatusByEmergencyId('', 'Delivered');
      await repo.updateStatusByEmergencyId(a.emergencyId!, 'Sent');
      expect((await repo.get(a.id))!.status, ReportStatus.pendingSync);
    });

    test('a draft or failed report is never promoted by a stray acknowledgement', () async {
      final draft = await repo.saveDraft(validDamage(repo).withMeta(emergencyId: 'stray'));
      await repo.updateStatusByEmergencyId('stray', 'Delivered');
      expect((await repo.get(draft.id))!.status, ReportStatus.draft);
    });

    test('SUBMITTED wording does not claim authorities reviewed the report', () {
      final text = ReportStatus.submitted.description.toLowerCase();
      expect(text, contains('does not confirm'));
      expect(text, contains('authorities'));
    });

    test('offline wording matches the spec', () {
      expect(ReportStatus.pendingSync.description,
          'Saved on this device. Will sync when connectivity is available.');
      expect(ReportStatus.draft.label, 'Draft');
    });
  });

  group('Offline behaviour', () {
    test('with no connectivity: create, save, edit and view still work', () async {
      dispatcher.error = Exception('offline: no peers, no internet');

      final draft = await repo.saveDraft(validDamage(repo));
      final edited = await repo.saveDraft((draft as DamageReport).copyWith(description: 'Updated: bridge is gone.'));
      expect((edited as DamageReport).description, startsWith('Updated'));

      final submitted = await repo.submit(edited);
      expect(submitted.status, ReportStatus.failed, reason: 'honest: it did not go anywhere');
      expect((await repo.list()), hasLength(1));
      expect((await repo.get(submitted.id)), isNotNull);
    });
  });

  group('History filtering', () {
    test('filters by report kind and returns newest first', () async {
      var clockTick = 0;
      final r = RecoveryRepository(
        dispatcher: dispatcher,
        clock: () => _t0.add(Duration(minutes: clockTick++)),
      );
      final damage = await r.submit(validDamage(r));
      final missing = await r.submit(validMissing(r));
      final request = await r.submit(validRequest(r));

      expect((await r.list()).map((x) => x.id), [request.id, missing.id, damage.id]);
      expect((await r.list(type: RecoveryReportType.damage)).map((x) => x.id), [damage.id]);
      expect((await r.list(type: RecoveryReportType.missingPerson)).map((x) => x.id), [missing.id]);
      expect((await r.list(type: RecoveryReportType.resourceRequest)).map((x) => x.id), [request.id]);
    });

    test('an empty history filters to empty', () async {
      expect(RecoveryRepository.filter(const [], RecoveryReportType.damage), isEmpty);
    });
  });

  group('Packet content (existing mesh path, unchanged protocol)', () {
    test('message is prefixed per kind and stays within the cap', () {
      final long = validDamage(repo).copyWith(description: 'x' * 2000);
      expect(long.toPacketMessage().length, lessThanOrEqualTo(480));
      expect(RecoveryReportType.damage.messagePrefix, '[RECOVERY:DAMAGE]');
      expect(RecoveryReportType.missingPerson.messagePrefix, '[RECOVERY:MISSING_PERSON]');
      expect(RecoveryReportType.resourceRequest.messagePrefix, '[RECOVERY:RESOURCE_REQUEST]');
      expect(validMissing(repo).toPacketMessage(), contains('Ramesh Kumar'));
    });

    test('priority follows severity/urgency but is never critical', () {
      for (final s in DamageSeverity.values) {
        expect(validDamage(repo).copyWith(severity: s).packetPriority,
            isNot(EmergencyPriority.critical));
      }
      for (final u in RequestUrgency.values) {
        expect(validRequest(repo).copyWith(urgency: u).packetPriority,
            isNot(EmergencyPriority.critical));
      }
      expect(validRequest(repo).copyWith(urgency: RequestUrgency.critical).packetPriority,
          EmergencyPriority.high);
      expect(validMissing(repo).packetPriority, EmergencyPriority.high);
    });
  });
}

class _ProbingDispatcher implements RecoveryDispatcher {
  _ProbingDispatcher(this._fn);
  final Future<String> Function(RecoveryRecord) _fn;

  @override
  Future<String> dispatch(RecoveryRecord record) => _fn(record);
}
