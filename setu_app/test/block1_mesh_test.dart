import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:setu_app/core/services/mesh_locator.dart';
import 'package:setu_app/mesh/enums/emergency_priority.dart';
import 'package:setu_app/mesh/models/ack_packet.dart';
import 'package:setu_app/mesh/models/alert_packet.dart';
import 'package:setu_app/mesh/models/emergency_packet.dart';
import 'package:setu_app/mesh/models/termination_packet.dart';
import 'package:setu_app/mesh/services/local_queue_service.dart';
import 'package:setu_app/mesh/services/mesh_metrics.dart';
import 'package:setu_app/mesh/services/mesh_policy.dart';
import 'package:setu_app/mesh/services/responder_registry.dart';
import 'package:setu_app/security/security_constants.dart';
import 'package:setu_app/services/backend_service.dart';
import 'package:setu_app/services/battery_service.dart';
import 'package:setu_app/services/power_mode.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'mesh_simulation.dart';

// BLOCK 1 (mesh-stability) regression tests: eager start, single relay
// path, upload outcomes, termination safety, exact queue cleanup,
// battery tiers. The native (Kotlin) halves of these guarantees are
// covered by PacketRelayEngineTest.kt under `gradlew :app:testDebugUnitTest`.

int _n = 0;

EmergencyPacket sos({
  String packetId = 'sos-b1',
  String emergencyId = 'e-b1',
  EmergencyPriority priority = EmergencyPriority.critical,
  int ttl = SecurityConstants.defaultTTL,
  String? nonce,
}) =>
    EmergencyPacket(
      packetId: packetId,
      senderId: 'originator-public-key',
      timestamp: DateTime.now().toUtc(),
      nonce: nonce ?? 'nonce-b1-${_n++}',
      ttl: ttl,
      hopCount: 0,
      signature: 'signature',
      emergencyId: emergencyId,
      latitude: 25.14,
      longitude: 82.56,
      message: 'Trapped',
      priority: priority,
    );

TerminationPacket termination({String emergencyId = 'e-b1', String sender = 'responder-public-key'}) =>
    TerminationPacket(
      packetId: 'term-b1-${_n++}',
      senderId: sender,
      timestamp: DateTime.now().toUtc(),
      nonce: 'nonce-b1-${_n++}',
      ttl: SecurityConstants.defaultTTL,
      hopCount: 0,
      signature: 'signature',
      emergencyId: emergencyId,
      responderId: 'r-1',
    );

Map<String, Object?> row(String id, String json) => {'packetId': id, 'jsonPayload': json};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('eager start', () {
    test('MeshLocator.start() attaches the native event listener and is a singleton', () async {
      SharedPreferences.setMockInitialValues({});
      var listens = 0;
      MockStreamHandlerEventSink? sink;
      final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockStreamHandler(
        const EventChannel('com.setu.mesh/events'),
        MockStreamHandler.inline(
          onListen: (args, events) {
            listens++;
            sink = events;
          },
        ),
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('com.setu.mesh/methods'),
        (call) async => null,
      );

      // Nothing has touched the locator yet: no listener.
      expect(listens, 0);

      final first = MeshLocator.start();
      final second = MeshLocator.start();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(identical(first, second), isTrue, reason: 'exactly one MeshLocator');
      expect(identical(first.meshService, MeshLocator.instance.meshService), isTrue,
          reason: 'exactly one MeshServiceImpl');
      expect(listens, 1, reason: 'exactly one native event subscription, attached at start');
      expect(sink, isNotNull);

      // The Dart side is really receiving native events before any SOS.
      sink!.success({'type': 'peer_connected', 'endpointId': 'ep-1'});
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(first.meshService.connectedPeerCount, 1);

      // A malformed event must not kill the subscription.
      sink!.success({'type': 'nonsense'});
      await Future<void>.delayed(const Duration(milliseconds: 20));
      sink!.success({'type': 'peer_connected', 'endpointId': 'ep-2'});
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(first.meshService.connectedPeerCount, 2);
    });
  });

  group('one relay path', () {
    test('native-relaying transport: Dart does NOT rebroadcast', () async {
      final mesh = await SimulatedMesh.chain(3);
      addTearDown(mesh.disposeAll);
      mesh.devices[1].nearbyFake.nativeRelay = true;

      await mesh.devices[0].mesh_.originate(sos());
      await mesh.settle();

      expect(mesh.devices[1].received, hasLength(1), reason: 'still delivered to Dart');
      expect(mesh.devices[1].transmitted, isEmpty,
          reason: 'relay belongs to the native layer; Dart must not also broadcast');
      expect(mesh.devices[2].received, isEmpty);
    });

    test('non-native transport: exactly one Dart relay per received packet', () async {
      final mesh = await SimulatedMesh.chain(3);
      addTearDown(mesh.disposeAll);

      await mesh.devices[0].mesh_.originate(sos());
      await mesh.settle();

      expect(mesh.devices[1].transmitted, hasLength(1));
      expect(mesh.devices[2].received, hasLength(1));
    });

    test('duplicate delivery of the same payload is dropped by the replay guard', () async {
      final mesh = await SimulatedMesh.chain(2);
      addTearDown(mesh.disposeAll);
      final bytes = Uint8List.fromList(utf8.encode(jsonEncode(sos().toJson())));

      mesh.devices[1].nearbyFake.inject(bytes);
      mesh.devices[1].nearbyFake.inject(bytes);
      await mesh.settle();

      expect(mesh.devices[1].received, hasLength(1));
    });
  });

  group('upload outcomes', () {
    test('accepted -> uploaded and ACK originated', () async {
      final mesh = await SimulatedMesh.chain(2);
      addTearDown(mesh.disposeAll);
      mesh.devices[1].backend.internetAvailable = true;

      await mesh.devices[0].mesh_.originate(sos());
      await mesh.settle();

      expect(mesh.devices[1].backend.uploadedPacketIds, ['sos-b1']);
      final acks = mesh.devices[1].transmitted
          .map((b) => jsonDecode(utf8.decode(b)) as Map<String, dynamic>)
          .where((j) => j['type'] == 'ack');
      expect(acks, isNotEmpty, reason: 'an accepted upload must be acknowledged');
    });

    test('rejected by backend -> NO ack, not counted delivered, not retried forever', () async {
      final mesh = await SimulatedMesh.chain(2);
      addTearDown(mesh.disposeAll);
      final backend = mesh.devices[1].backend
        ..internetAvailable = true
        ..nextOutcome = UploadOutcome.rejected;

      await mesh.devices[0].mesh_.originate(sos());
      await mesh.settle();

      final acks = mesh.devices[1].transmitted
          .map((b) => jsonDecode(utf8.decode(b)) as Map<String, dynamic>)
          .where((j) => j['type'] == 'ack');
      expect(acks, isEmpty, reason: 'must not confirm delivery of a packet the backend refused');
      expect(backend.uploadedPacketIds, isEmpty);
      expect(mesh.devices[1].queue.pendingCount, 0, reason: 'a permanent rejection must stop retrying');
    });

    test('duplicate (backend already holds the identical packet) -> delivered, ACK originated once', () async {
      final mesh = await SimulatedMesh.chain(2);
      addTearDown(mesh.disposeAll);
      mesh.devices[1].backend
        ..internetAvailable = true
        ..nextOutcome = UploadOutcome.duplicate;

      await mesh.devices[0].mesh_.originate(sos());
      await mesh.settle();

      final acks = mesh.devices[1].transmitted
          .map((b) => jsonDecode(utf8.decode(b)) as Map<String, dynamic>)
          .where((j) => j['type'] == 'ack');
      expect(acks, hasLength(1), reason: 'DUPLICATE means the backend holds it: delivered, one ACK');
      expect(mesh.devices[1].queue.pendingCount, 0);
    });

    test('network failure -> no ACK and the packet stays queued', () async {
      final mesh = await SimulatedMesh.chain(2);
      addTearDown(mesh.disposeAll);
      mesh.devices[1].backend
        ..internetAvailable = true
        ..nextOutcome = UploadOutcome.failed;

      await mesh.devices[0].mesh_.originate(sos());
      await mesh.settle();

      final acks = mesh.devices[1].transmitted
          .map((b) => jsonDecode(utf8.decode(b)) as Map<String, dynamic>)
          .where((j) => j['type'] == 'ack');
      expect(acks, isEmpty);
      expect(mesh.devices[1].queue.pendingCount, 1);
    });

    test('transient failure keeps the packet pending for retry', () async {
      final mesh = await SimulatedMesh.chain(2);
      addTearDown(mesh.disposeAll);
      mesh.devices[1].backend
        ..internetAvailable = true
        ..nextOutcome = UploadOutcome.failed;

      await mesh.devices[0].mesh_.originate(sos());
      await mesh.settle();

      expect(mesh.devices[1].queue.pendingCount, 1);
    });

    test('ACK and alert packets are not put in the durable upload queue', () async {
      final mesh = await SimulatedMesh.chain(2);
      addTearDown(mesh.disposeAll);

      final ack = AckPacket(
        packetId: 'ack-1',
        senderId: 'exit-node-public-key',
        timestamp: DateTime.now().toUtc(),
        nonce: 'nonce-ack-${_n++}',
        ttl: 5,
        hopCount: 0,
        signature: 'signature',
        originalPacketId: 'sos-x',
        emergencyId: 'e-x',
      );
      final alert = AlertPacket(
        packetId: 'alert-1',
        senderId: 'someone-public-key',
        timestamp: DateTime.now().toUtc(),
        nonce: 'nonce-alert-${_n++}',
        ttl: 5,
        hopCount: 0,
        signature: 'signature',
        incidentType: 'fire',
        latitude: 1.0,
        longitude: 2.0,
      );
      await mesh.devices[0].mesh_.originate(ack);
      await mesh.devices[0].mesh_.originate(alert);
      await mesh.settle();

      expect(mesh.devices[0].queue.storedCount, 0);
      expect(mesh.devices[1].queue.storedCount, 0);
      expect(mesh.devices[1].received, hasLength(2), reason: 'still relayed/delivered on the mesh');
    });

    test('BackendService.classifyIngestResponse', () {
      String body(List accepted, List rejected) =>
          jsonEncode({'accepted': accepted, 'rejected': rejected});
      expect(BackendService.classifyIngestResponse(body([{'packet_id': 'p'}], []), 'p'),
          UploadOutcome.accepted);
      expect(
          BackendService.classifyIngestResponse(
              body([], [{'packet_id': 'p', 'reason': 'duplicate packet_id'}]), 'p'),
          UploadOutcome.duplicate);
      expect(
          BackendService.classifyIngestResponse(
              body([], [{'packet_id': 'p', 'reason': 'duplicate packet_id (race condition on concurrent insert)'}]),
              'p'),
          UploadOutcome.duplicate);
      for (final reason in ['invalid signature', 'TTL expired', 'schema validation failed (x)', 'unauthorized responder']) {
        expect(BackendService.classifyIngestResponse(body([], [{'packet_id': 'p', 'reason': reason}]), 'p'),
            UploadOutcome.rejected,
            reason: reason);
      }
      expect(BackendService.classifyIngestResponse(body([], []), 'p'), UploadOutcome.failed);
      expect(BackendService.classifyIngestResponse('<html>captive portal</html>', 'p'), UploadOutcome.failed);
      expect(BackendService.classifyIngestResponse('{"accepted": 1}', 'p'), UploadOutcome.failed);
    });

    test('BackendService.uploadPacketDetailed over HTTP', () async {
      Future<UploadOutcome> run(http.Response Function(http.Request) handler) {
        final service = BackendService(baseUrl: 'https://x.test', client: http_testing.MockClient((r) async => handler(r)));
        return service.uploadPacketDetailed(sos(packetId: 'p1'));
      }

      expect(await run((_) => http.Response('{"accepted":[{"packet_id":"p1"}],"rejected":[]}', 200)),
          UploadOutcome.accepted);
      expect(await run((_) => http.Response('{"accepted":[],"rejected":[{"packet_id":"p1","reason":"invalid signature"}]}', 200)),
          UploadOutcome.rejected, reason: 'HTTP 200 with a rejection must NOT count as delivered');
      expect(await run((_) => http.Response('boom', 500)), UploadOutcome.failed);
      expect(await run((_) => http.Response('<html/>', 200)), UploadOutcome.failed);
      final throwing = BackendService(
          baseUrl: 'https://x.test', client: http_testing.MockClient((_) async => throw Exception('offline')));
      expect(await throwing.uploadPacketDetailed(sos()), UploadOutcome.failed);
      // Wrapper used by SosRepository.
      final ok = BackendService(
          baseUrl: 'https://x.test',
          client: http_testing.MockClient((_) async => http.Response(
              '{"accepted":[],"rejected":[{"packet_id":"sos-b1","reason":"invalid signature"}]}', 200)));
      expect(await ok.uploadPacket(sos()), isFalse);
    });
  });

  group('termination safety', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await ResponderRegistry.instance.resetForTesting();
    });

    Future<bool> closedAfter(SimulatedMesh mesh, TerminationPacket t) async {
      await mesh.devices[0].mesh_.originate(sos(emergencyId: t.emergencyId));
      await mesh.settle();
      await mesh.devices[0].mesh_.originate(t);
      await mesh.settle();
      await mesh.devices[0].mesh_.originate(sos(packetId: 'late', emergencyId: t.emergencyId));
      await mesh.settle();
      // Closed <=> the late packet for that emergency was dropped.
      return !mesh.devices[1].received.any((p) => p.packetId == 'late');
    }

    test('authorized responder closes the emergency (and native is told)', () async {
      ResponderRegistry.instance.syncFromBackend(['responder-public-key']);
      final mesh = await SimulatedMesh.chain(2);
      addTearDown(mesh.disposeAll);
      expect(await closedAfter(mesh, termination()), isTrue);
      expect(mesh.devices[1].nearbyFake.closedEmergencies, contains('e-b1'));
    });

    test('unauthorized key does not close it', () async {
      ResponderRegistry.instance.syncFromBackend(['responder-public-key']);
      final mesh = await SimulatedMesh.chain(2);
      addTearDown(mesh.disposeAll);
      expect(await closedAfter(mesh, termination(sender: 'attacker-key')), isFalse);
      expect(mesh.devices[1].nearbyFake.closedEmergencies, isEmpty);
      expect(MeshMetrics.instance.terminationsRejected, greaterThan(0));
    });

    test('EMPTY registry fails closed', () async {
      final mesh = await SimulatedMesh.chain(2);
      addTearDown(mesh.disposeAll);
      expect(ResponderRegistry.instance.checkResponder('responder-public-key'), (false, false));
      expect(await closedAfter(mesh, termination()), isFalse);
    });

    test('registry survives a restart (persisted), and is still fail-closed for others', () async {
      ResponderRegistry.instance.syncFromBackend(['responder-public-key']);
      await Future<void>.delayed(const Duration(milliseconds: 20)); // let the persist write land
      ResponderRegistry.instance.simulateRestartForTesting();
      expect(ResponderRegistry.instance.trustedCount, 0, reason: 'memory forgotten by the "restart"');

      await ResponderRegistry.instance.ensureLoaded();
      expect(ResponderRegistry.instance.checkResponder('responder-public-key'), (true, true));
      expect(ResponderRegistry.instance.checkResponder('attacker-key'), (false, true));
    });

    test('an empty backend answer replaces the persisted set (no trusted responders)', () async {
      ResponderRegistry.instance.syncFromBackend(['responder-public-key']);
      ResponderRegistry.instance.syncFromBackend([]);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      ResponderRegistry.instance.simulateRestartForTesting();
      await ResponderRegistry.instance.ensureLoaded();
      expect(ResponderRegistry.instance.checkResponder('responder-public-key').$1, isFalse);
    });
  });

  group('exact emergency cleanup (no LIKE wildcards)', () {
    String payload(String id, String emergencyId, {String message = 'm'}) => jsonEncode({
          'packet_id': id,
          'emergency_id': emergencyId,
          'message': message,
        });

    final rows = <Map<String, Object?>>[
      row('a', payload('a', 'fire-1')),
      row('b', payload('b', 'fire-10')),
      row('c', payload('c', 'fire_1')),
      row('d', payload('d', 'x%y')),
      row('e', payload('e', 'unrelated', message: 'contains "emergency_id":"fire-1" text')),
      row('f', 'not json'),
      row('g', jsonEncode({'packet_id': 'g'})),
    ];

    test('normal alphanumeric id matches only itself', () {
      expect(LocalQueueService.packetIdsForEmergency(rows, 'fire-1'), ['a']);
    });

    test('"%" matches nothing (was: everything)', () {
      expect(LocalQueueService.packetIdsForEmergency(rows, '%'), isEmpty);
    });

    test('"_" is not a single-char wildcard', () {
      expect(LocalQueueService.packetIdsForEmergency(rows, 'fire_1'), ['c']);
      expect(LocalQueueService.packetIdsForEmergency(rows, '_'), isEmpty);
    });

    test('a literal "%" inside an id matches that exact id only', () {
      expect(LocalQueueService.packetIdsForEmergency(rows, 'x%y'), ['d']);
      expect(LocalQueueService.packetIdsForEmergency(rows, 'x%'), isEmpty);
    });

    test('empty id, malformed rows, rows without emergency_id never match', () {
      expect(LocalQueueService.packetIdsForEmergency(rows, ''), isEmpty);
      expect(LocalQueueService.packetIdsForEmergency(rows, 'unrelated'), ['e']);
    });
  });

  group('battery tiers', () {
    test('thresholds: >50 full, 20..50 balanced, <20 power saver', () {
      expect(BatteryService.modeForLevel(100), PowerMode.full);
      expect(BatteryService.modeForLevel(51), PowerMode.full);
      expect(BatteryService.modeForLevel(50), PowerMode.balanced);
      expect(BatteryService.modeForLevel(20), PowerMode.balanced);
      expect(BatteryService.modeForLevel(19), PowerMode.powerSaver);
      expect(BatteryService.modeForLevel(0), PowerMode.powerSaver);
    });

    test('policy per tier: relay, upload and discovery interval', () {
      final full = MeshPolicy.fromPowerMode(BatteryService.modeForLevel(80));
      final balanced = MeshPolicy.fromPowerMode(BatteryService.modeForLevel(35));
      final saver = MeshPolicy.fromPowerMode(BatteryService.modeForLevel(10));
      expect((full.allowRelay, full.allowUpload, full.discoveryInterval.inSeconds), (true, true, 5));
      expect((balanced.allowRelay, balanced.allowUpload, balanced.discoveryInterval.inSeconds), (true, true, 15));
      expect((saver.allowRelay, saver.allowUpload, saver.discoveryInterval.inSeconds), (false, false, 30));
    });

    test('recovery: <20 -> >20 restores relay and upload', () {
      expect(MeshPolicy.fromPowerMode(BatteryService.modeForLevel(15)).allowRelay, isFalse);
      final recovered = MeshPolicy.fromPowerMode(BatteryService.modeForLevel(25));
      expect(recovered.allowRelay, isTrue);
      expect(recovered.allowUpload, isTrue);
    });
  });
}
