// =====================================================
// SETU Project
// Module : Recovery hardening (concurrency, dispatcher, corrupt data)
// =====================================================
//
// Each group pins one audited failure mode. They exist because the
// behaviour is easy to get wrong and invisible in normal use: lost
// updates, stale writes, duplicate sends and a transport that can fail
// after it has already queued the packet.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart' show Permission;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:setu_app/features/location/data/models/location_model.dart';
import 'package:setu_app/features/location/data/services/location_service.dart';
import 'package:setu_app/features/onboarding/data/services/mesh_permission_service.dart';
import 'package:setu_app/features/preparedness/data/models/emergency_contact.dart';
import 'package:setu_app/features/preparedness/data/models/emergency_plan.dart';
import 'package:setu_app/features/preparedness/data/repositories/emergency_contacts_repository.dart';
import 'package:setu_app/features/preparedness/data/repositories/emergency_plan_repository.dart';
import 'package:setu_app/features/recovery/data/models/damage_report.dart';
import 'package:setu_app/features/recovery/data/models/recovery_enums.dart';
import 'package:setu_app/features/recovery/data/models/recovery_record.dart';
import 'package:setu_app/features/recovery/data/models/recovery_report_type.dart';
import 'package:setu_app/features/recovery/data/models/report_status.dart';
import 'package:setu_app/features/recovery/data/repositories/recovery_repository.dart';
import 'package:setu_app/features/recovery/data/services/recovery_dispatcher.dart';
import 'package:setu_app/features/recovery/data/services/recovery_packet_builder.dart';
import 'package:setu_app/features/recovery/data/services/recovery_report_store.dart';
import 'package:setu_app/mesh/enums/emergency_priority.dart';
import 'package:setu_app/mesh/models/emergency_packet.dart';

DamageReport _valid(RecoveryRepository repo, {String location = 'NH-44 bridge'}) =>
    (repo.newDraft(RecoveryReportType.damage) as DamageReport).copyWith(
      category: DamageCategory.road,
      severity: DamageSeverity.high,
      location: location,
      description: 'Road washed away, vehicles cannot pass.',
    );

class _Dispatcher implements RecoveryDispatcher {
  _Dispatcher({this.onDispatch});

  final Future<String> Function(RecoveryRecord, PacketBuiltCallback?)? onDispatch;
  int calls = 0;

  @override
  Future<String> dispatch(RecoveryRecord record, {PacketBuiltCallback? onPacketBuilt}) async {
    calls++;
    if (onDispatch != null) return onDispatch!(record, onPacketBuilt);
    final id = 'e$calls';
    await onPacketBuilt?.call(id);
    return id;
  }
}

class _Perms implements MeshPermissionService {
  _Perms({this.granted = true});
  final bool granted;
  int requests = 0;

  @override
  Future<bool> hasAll() async => granted;

  @override
  Future<List<Permission>> requestAll() async {
    requests++;
    return granted ? [] : [Permission.bluetooth];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Location extends LocationService {
  _Location({this.fail = false});
  final bool fail;
  int calls = 0;

  @override
  Future<LocationModel> getCurrentLocation() async {
    calls++;
    if (fail) throw Exception('Location service is disabled.');
    return const LocationModel(latitude: 12.5, longitude: 77.25);
  }
}

class _Builder implements RecoveryPacketBuilder {
  final built = <Map<String, Object?>>[];

  @override
  Future<EmergencyPacket> buildRecoveryPacket({
    required RecoveryReportType type,
    required double latitude,
    required double longitude,
    required String message,
    required EmergencyPriority priority,
  }) async {
    built.add({'type': type, 'lat': latitude, 'lng': longitude, 'msg': message, 'prio': priority});
    final id = 'pkt-${built.length}';
    return EmergencyPacket(
      packetId: id,
      senderId: 'sender',
      timestamp: DateTime.utc(2026, 9, 1),
      nonce: 'n$id',
      ttl: 5,
      hopCount: 0,
      signature: 'sig',
      emergencyId: id,
      latitude: latitude,
      longitude: longitude,
      message: '${type.messagePrefix} $message',
      priority: priority,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    RecoveryRepository.resetForTesting();
  });

  group('Store: concurrent writers never lose an update', () {
    test('many simultaneous upserts from separate store instances all survive', () async {
      final repo = RecoveryRepository(dispatcher: _Dispatcher());
      final drafts = [for (var i = 0; i < 40; i++) _valid(repo, location: 'Ward $i')];
      await Future.wait([
        for (final d in drafts) RecoveryReportStore().upsert(d),
      ]);
      final stored = await RecoveryReportStore().all();
      expect(stored.map((r) => r.id).toSet(), drafts.map((r) => r.id).toSet());
    });

    test('an acknowledgement racing a save of another report loses neither', () async {
      final repo = RecoveryRepository(dispatcher: _Dispatcher());
      final sent = await repo.submit(_valid(repo));
      final another = _valid(repo, location: 'Ward 9');

      await Future.wait([
        repo.updateStatusByEmergencyId(sent.emergencyId!, 'Delivered'),
        RecoveryRepository(dispatcher: _Dispatcher()).saveDraft(another),
      ]);

      expect((await repo.get(sent.id))!.status, ReportStatus.submitted);
      expect((await repo.get(another.id))!.status, ReportStatus.draft);
    });

    test('a failed write does not block the writes queued behind it', () async {
      final store = RecoveryReportStore();
      final repo = RecoveryRepository(dispatcher: _Dispatcher());
      // A record that cannot be encoded fails inside the queue...
      final poisoned = (repo.newDraft(RecoveryReportType.damage) as DamageReport)
          .copyWith(description: 'x')
          .withMeta(lastError: 'e');
      final bad = store.upsert(_Unencodable(poisoned));
      await expectLater(bad, throwsA(anything));
      // ...and the next write still goes through.
      final good = _valid(repo);
      await store.upsert(good);
      expect((await store.byId(good.id)), isNotNull);
    });
  });

  group('Store: unreadable entries are preserved, not destroyed', () {
    Future<List<String>> raw() async =>
        (await SharedPreferences.getInstance()).getStringList('recovery_reports_v1')!;

    test('corrupt and unknown-type entries survive later upserts and deletes', () async {
      final repo = RecoveryRepository(dispatcher: _Dispatcher());
      final draft = await repo.saveDraft(_valid(repo));
      final prefs = await SharedPreferences.getInstance();
      const corrupt = '{not json';
      final future = jsonEncode({'id': 'FUT-1', 'type': 'from_a_newer_version', 'x': 1});
      await prefs.setStringList('recovery_reports_v1', [corrupt, future, ...await raw()]);

      // The readable list ignores them...
      expect((await repo.list()).map((r) => r.id), [draft.id]);

      // ...but writing another report must not drop them.
      await repo.saveDraft(_valid(repo, location: 'Ward 2'));
      await repo.deleteDraft(draft.id);
      final after = await raw();
      expect(after, containsAll([corrupt, future]));
      expect((await repo.list()), hasLength(1));
    });

    test('the size cap never evicts an unreadable entry', () async {
      final repo = RecoveryRepository(dispatcher: _Dispatcher());
      final prefs = await SharedPreferences.getInstance();
      const corrupt = '{not json';
      await prefs.setStringList('recovery_reports_v1', [corrupt]);
      final base = DateTime.utc(2026, 9, 1);
      for (var i = 0; i < RecoveryReportStore.maxEntries + 3; i++) {
        await RecoveryReportStore().upsert(_valid(repo).withMeta(
          status: ReportStatus.pendingSync,
          updatedAt: base.add(Duration(minutes: i)),
        ));
      }
      expect(await raw(), contains(corrupt));
      expect((await RecoveryReportStore().all()).length, RecoveryReportStore.maxEntries);
    });

    test('the cap evicts by last update, not by list position', () async {
      final repo = RecoveryRepository(dispatcher: _Dispatcher());
      final base = DateTime.utc(2026, 9, 1);
      final first = _valid(repo).withMeta(status: ReportStatus.pendingSync, updatedAt: base);
      await RecoveryReportStore().upsert(first);
      for (var i = 1; i <= RecoveryReportStore.maxEntries - 1; i++) {
        await RecoveryReportStore().upsert(_valid(repo).withMeta(
          status: ReportStatus.pendingSync,
          updatedAt: base.add(Duration(minutes: i)),
        ));
      }
      // Touch the very first (oldest-positioned) report so it is now newest.
      await RecoveryReportStore().upsert(first.withMeta(
        status: ReportStatus.submitted,
        updatedAt: base.add(const Duration(days: 1)),
      ));
      // One more report pushes the total over the cap.
      await RecoveryReportStore().upsert(_valid(repo).withMeta(
        status: ReportStatus.pendingSync,
        updatedAt: base.add(const Duration(days: 2)),
      ));
      final ids = (await RecoveryReportStore().all()).map((r) => r.id).toSet();
      expect(ids, contains(first.id), reason: 'recently updated, must not be evicted');
      expect(ids.length, RecoveryReportStore.maxEntries);
    });
  });

  group('Repository: the stored status governs, not the caller\'s copy', () {
    test('a stale draft copy cannot reset a queued report to draft', () async {
      final dispatcher = _Dispatcher();
      final repo = RecoveryRepository(dispatcher: dispatcher);
      final draft = await repo.saveDraft(_valid(repo));
      final staleCopy = draft; // the form still holds this
      final queued = await repo.submit(draft);
      expect(queued.status, ReportStatus.pendingSync);

      await expectLater(repo.saveDraft(staleCopy), throwsStateError);
      expect((await repo.get(draft.id))!.status, ReportStatus.pendingSync);
    });

    test('a stale copy cannot be submitted again (no second packet)', () async {
      final dispatcher = _Dispatcher();
      final repo = RecoveryRepository(dispatcher: dispatcher);
      final draft = await repo.saveDraft(_valid(repo));
      await repo.submit(draft);
      await expectLater(repo.submit(draft), throwsStateError);
      expect(dispatcher.calls, 1);
    });

    test('a stale copy cannot pull an acknowledged report back to a draft', () async {
      final repo = RecoveryRepository(dispatcher: _Dispatcher());
      final draft = await repo.saveDraft(_valid(repo));
      final sent = await repo.submit(draft);
      await repo.updateStatusByEmergencyId(sent.emergencyId!, 'Delivered');
      await expectLater(repo.saveDraft(draft), throwsStateError);
      expect((await repo.get(draft.id))!.status, ReportStatus.submitted);
    });

    test('a report that was never stored is judged by the copy in hand', () async {
      final dispatcher = _Dispatcher();
      final repo = RecoveryRepository(dispatcher: dispatcher);
      final fresh = _valid(repo);
      expect((await repo.submit(fresh)).status, ReportStatus.pendingSync);
      expect(dispatcher.calls, 1);
    });
  });

  group('Repository: duplicate submissions', () {
    test('two simultaneous submits of one report send exactly one packet', () async {
      final gate = Completer<void>();
      final dispatcher = _Dispatcher(onDispatch: (r, built) async {
        await built?.call('e-once');
        await gate.future; // hold the first submit in flight
        return 'e-once';
      });
      final repo = RecoveryRepository(dispatcher: dispatcher);
      final report = _valid(repo);

      final first = repo.submit(report);
      final second = repo.submit(report);
      // Let both reach the repository, then release the transport.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      gate.complete();

      expect((await first).status, ReportStatus.pendingSync);
      await expectLater(second, throwsStateError);
      expect(dispatcher.calls, 1);
      expect((await repo.list()), hasLength(1));
    });

    test('simultaneous retries of one failed report send one packet', () async {
      var fail = true;
      final dispatcher = _Dispatcher(onDispatch: (r, built) async {
        if (fail) throw const RecoveryDispatchException('no route');
        await built?.call('e-retry');
        return 'e-retry';
      });
      final repo = RecoveryRepository(dispatcher: dispatcher);
      final failed = await repo.submit(_valid(repo));
      expect(failed.status, ReportStatus.failed);

      fail = false;
      final results = await Future.wait([
        repo.retry(failed.id).then<Object>((r) => r, onError: (Object e) => e),
        repo.retry(failed.id).then<Object>((r) => r, onError: (Object e) => e),
      ]);
      expect(results.whereType<RecoveryRecord>(), hasLength(1));
      expect(results.whereType<StateError>(), hasLength(1));
      expect(dispatcher.calls, 2, reason: 'the failed attempt plus one successful retry');
    });
  });

  group('Repository: emergencyId is stored before the transport hand-off', () {
    test('an acknowledgement can be matched even if the hand-off is still running',
        () async {
      final store = RecoveryReportStore();
      String? idSeenInStore;
      final dispatcher = _Dispatcher(onDispatch: (record, built) async {
        await built!('e-early');
        // Mid hand-off: the report must already carry its emergencyId.
        idSeenInStore = (await store.byId(record.id))?.emergencyId;
        return 'e-early';
      });
      final repo = RecoveryRepository(store: store, dispatcher: dispatcher);
      await repo.submit(_valid(repo));
      expect(idSeenInStore, 'e-early');
    });

    test('an ACK that lands during dispatch is applied once dispatch finishes', () async {
      late RecoveryRepository repo;
      final dispatcher = _Dispatcher(onDispatch: (record, built) async {
        await built!('e-race');
        // The acknowledgement arrives while the hand-off is still running.
        unawaited(repo.updateStatusByEmergencyId('e-race', 'Delivered'));
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return 'e-race';
      });
      repo = RecoveryRepository(dispatcher: dispatcher);
      final result = await repo.submit(_valid(repo));
      expect(result.status, ReportStatus.pendingSync, reason: 'returned before the ack applied');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect((await repo.get(result.id))!.status, ReportStatus.submitted);
    });

    test('a failed dispatch never becomes submitted through a late ack', () async {
      final repo = RecoveryRepository(dispatcher: _Dispatcher(onDispatch: (r, built) async {
        await built!('e-late');
        throw const RecoveryDispatchException('mesh down');
      }));
      final failed = await repo.submit(_valid(repo));
      expect(failed.status, ReportStatus.failed);
      await repo.updateStatusByEmergencyId('e-late', 'Delivered');
      expect((await repo.get(failed.id))!.status, ReportStatus.failed);
    });
  });

  group('MeshRecoveryDispatcher', () {
    late _Builder builder;
    late List<String> order;

    MeshRecoveryDispatcher make({
      _Perms? perms,
      _Location? location,
      Future<void> Function(EmergencyPacket)? originate,
      Future<bool> Function(String)? queued,
    }) {
      builder = _Builder();
      order = [];
      return MeshRecoveryDispatcher(
        permissionService: perms ?? _Perms(),
        locationService: location ?? _Location(),
        packetBuilder: builder,
        originate: originate ?? (p) async => order.add('originate'),
        isDurablyQueued: queued ?? (_) async => false,
      );
    }

    test('builds the packet from the report: message, priority and coordinates', () async {
      final repo = RecoveryRepository(dispatcher: _Dispatcher());
      final report = _valid(repo).copyWith(latitude: 1.5, longitude: 2.5);
      final location = _Location();
      final d = make(location: location);

      final id = await d.dispatch(report);

      expect(id, 'pkt-1');
      final args = builder.built.single;
      expect(args['type'], RecoveryReportType.damage);
      expect(args['msg'], report.toPacketMessage());
      expect(args['prio'], report.packetPriority);
      expect(args['lat'], 1.5);
      expect(args['lng'], 2.5);
      expect(location.calls, 0, reason: 'the fix captured on the form is reused');
    });

    test('takes a device fix only when the form has none', () async {
      final repo = RecoveryRepository(dispatcher: _Dispatcher());
      final d = make();
      await d.dispatch(_valid(repo));
      expect(builder.built.single['lat'], 12.5);
      expect(builder.built.single['lng'], 77.25);
    });

    test('missing permissions: nothing is built or sent', () async {
      final repo = RecoveryRepository(dispatcher: _Dispatcher());
      final perms = _Perms(granted: false);
      final d = make(perms: perms);
      await expectLater(d.dispatch(_valid(repo)), throwsA(isA<RecoveryDispatchException>()));
      expect(perms.requests, 1);
      expect(builder.built, isEmpty);
      expect(order, isEmpty);
    });

    test('no location available: nothing is built or sent', () async {
      final repo = RecoveryRepository(dispatcher: _Dispatcher());
      final d = make(location: _Location(fail: true));
      await expectLater(
        d.dispatch(_valid(repo)),
        throwsA(predicate((e) => e is RecoveryDispatchException && '$e'.contains('location'))),
      );
      expect(builder.built, isEmpty);
    });

    test('reports the packet id before the hand-off, in that order', () async {
      final repo = RecoveryRepository(dispatcher: _Dispatcher());
      final d = make();
      final events = <String>[];
      final d2 = MeshRecoveryDispatcher(
        permissionService: _Perms(),
        locationService: _Location(),
        packetBuilder: _Builder(),
        originate: (p) async => events.add('originate'),
        isDurablyQueued: (_) async => false,
      );
      await d2.dispatch(_valid(repo), onPacketBuilt: (id) async => events.add('built:$id'));
      expect(events, ['built:pkt-1', 'originate']);
      expect(d, isNotNull);
    });

    test('a hand-off failure AFTER the packet was durably queued counts as queued',
        () async {
      final repo = RecoveryRepository(dispatcher: _Dispatcher());
      final d = make(
        originate: (p) async => throw Exception('SERVICE_UNAVAILABLE'),
        queued: (id) async => id == 'pkt-1',
      );
      // Retrying would send the same report twice, so this is not a failure.
      expect(await d.dispatch(_valid(repo)), 'pkt-1');
    });

    test('a hand-off failure with nothing queued is a real failure', () async {
      final repo = RecoveryRepository(dispatcher: _Dispatcher());
      final d = make(originate: (p) async => throw Exception('boom'));
      await expectLater(d.dispatch(_valid(repo)), throwsA(isA<RecoveryDispatchException>()));
    });

    test('if the queue cannot be inspected, the failure is reported honestly', () async {
      final repo = RecoveryRepository(dispatcher: _Dispatcher());
      final d = make(
        originate: (p) async => throw Exception('boom'),
        queued: (_) async => throw StateError('db closed'),
      );
      await expectLater(d.dispatch(_valid(repo)), throwsA(isA<RecoveryDispatchException>()));
    });

    test('through the repository: queued-then-failed shows pending sync, not failed',
        () async {
      final dispatcher = make(
        originate: (p) async => throw Exception('SERVICE_UNAVAILABLE'),
        queued: (_) async => true,
      );
      final repo = RecoveryRepository(dispatcher: dispatcher);
      final result = await repo.submit(_valid(repo));
      expect(result.status, ReportStatus.pendingSync);
      expect(result.emergencyId, 'pkt-1');
      expect(builder.built, hasLength(1));
    });
  });

  group('Emergency contacts survive unreadable saved contacts', () {
    test('a corrupt SOS-contacts list still shows the emergency plan contacts', () async {
      SharedPreferences.setMockInitialValues({'emergency_contacts': '{corrupt'});
      await EmergencyPlanRepository().save(const EmergencyPlan(
        primaryName: 'Asha',
        primaryPhone: '9876543210',
      ));
      final contacts = await EmergencyContactsRepository().load();
      expect(contacts.map((c) => c.name), ['Asha']);
      expect(contacts.single.source, EmergencyContactSource.plan);
    });
  });
}

/// A record whose JSON cannot be encoded, to make a queued write fail.
class _Unencodable extends DamageReport {
  _Unencodable(DamageReport base)
      : super(
          id: base.id,
          status: base.status,
          createdAt: base.createdAt,
          updatedAt: base.updatedAt,
        );

  @override
  Map<String, dynamic> toJson() => {'id': id, 'bad': Object()};
}
