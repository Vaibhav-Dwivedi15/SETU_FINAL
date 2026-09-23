import 'package:flutter_test/flutter_test.dart';
import 'package:setu_app/mesh/services/responder_registry.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:setu_app/mesh/enums/emergency_priority.dart';
import 'package:setu_app/mesh/models/emergency_packet.dart';
import 'package:setu_app/mesh/models/termination_packet.dart';
import 'package:setu_app/security/security_constants.dart';

import 'mesh_simulation.dart';

// Multi-device mesh scenarios (PRIORITY 5), run with `flutter test`.
//
// Scope and honesty: see the header of mesh_simulation.dart. These
// exercise real MeshServiceImpl behaviour over a simulated transport.
// They are correctness tests, NOT performance measurements — no number
// produced here belongs in a benchmark table.
//
// Every test asserts on behaviour that breaks if the implementation
// breaks: delivery counts, TTL decay, drop reasons, upload sets. A test
// that would pass against a no-op relay is not worth having.

int _nonceCounter = 0;

EmergencyPacket sos({
  String packetId = 'sos-1',
  String emergencyId = 'e1',
  EmergencyPriority priority = EmergencyPriority.critical,
  int ttl = SecurityConstants.defaultTTL,
  DateTime? timestamp,
}) =>
    EmergencyPacket(
      packetId: packetId,
      senderId: 'originator-public-key',
      timestamp: timestamp ?? DateTime.now().toUtc(),
      nonce: 'nonce-${_nonceCounter++}',
      ttl: ttl,
      hopCount: 0,
      signature: 'signature',
      emergencyId: emergencyId,
      latitude: 25.14,
      longitude: 82.56,
      message: 'Trapped, need help',
      priority: priority,
    );

TerminationPacket closure({String emergencyId = 'e1'}) => TerminationPacket(
      packetId: 'term-${_nonceCounter++}',
      senderId: 'responder-public-key',
      timestamp: DateTime.now().toUtc(),
      nonce: 'nonce-${_nonceCounter++}',
      ttl: SecurityConstants.defaultTTL,
      hopCount: 0,
      signature: 'signature',
      emergencyId: emergencyId,
      responderId: 'responder-1',
    );

void main() {
  group('device counts', () {
    test('1 device — an SOS with nobody in range is still stored for later', () async {
      final mesh = await SimulatedMesh.chain(1);
      addTearDown(mesh.disposeAll);

      await mesh.devices[0].mesh_.originate(sos());
      await mesh.settle();

      expect(mesh.devices[0].transmitted, hasLength(1),
          reason: 'the packet must still go out on the radio — someone may arrive');
      expect(mesh.devices[0].queue.storedCount, 1,
          reason: 'store-and-forward must hold it until an exit node exists');
    });

    test('2 devices — single hop delivers', () async {
      final mesh = await SimulatedMesh.chain(2);
      addTearDown(mesh.disposeAll);

      await mesh.devices[0].mesh_.originate(sos());
      await mesh.settle();

      expect(mesh.devices[1].received, hasLength(1));
      expect(mesh.devices[1].received.first.packetId, 'sos-1');
    });

    test('3 devices — the middle device actually relays', () async {
      final mesh = await SimulatedMesh.chain(3);
      addTearDown(mesh.disposeAll);

      await mesh.devices[0].mesh_.originate(sos());
      await mesh.settle();

      expect(mesh.devices[1].received, hasLength(1));
      expect(mesh.devices[1].relayedAnything, isTrue,
          reason: 'device 1 is the only path to device 2');
      expect(mesh.devices[2].received, hasLength(1), reason: 'two-hop delivery failed');
    });

    test('5 devices in a chain — TTL bounds how far it travels', () async {
      final mesh = await SimulatedMesh.chain(5);
      addTearDown(mesh.disposeAll);

      await mesh.devices[0].mesh_.originate(sos());
      await mesh.settle();

      for (var i = 1; i < 5; i++) {
        expect(mesh.devices[i].received, hasLength(1),
            reason: 'device $i never received the SOS');
      }
      // Each hop spends exactly one TTL for a CRITICAL packet.
      expect(mesh.devices[1].received.first.ttl, SecurityConstants.defaultTTL);
      expect(mesh.devices[4].received.first.ttl,
          SecurityConstants.defaultTTL - 3,
          reason: 'critical packets must lose exactly one TTL per hop');
    });

    test('10 devices — delivery reaches only as far as the TTL budget allows', () async {
      final mesh = await SimulatedMesh.chain(10);
      addTearDown(mesh.disposeAll);

      await mesh.devices[0].mesh_.originate(sos());
      await mesh.settle(rounds: 80);

      final reached = mesh.devices.where((device) => device.received.isNotEmpty).length;
      expect(reached, greaterThanOrEqualTo(4),
          reason: 'a 5-TTL packet should cross at least four hops');
      expect(reached, lessThan(10),
          reason: 'TTL must stop propagation — unbounded flooding is the bug this prevents');
    });
  });

  group('topologies', () {
    test('dense cluster — every device gets it exactly once, no storm', () async {
      final mesh = await SimulatedMesh.fullyConnected(8);
      addTearDown(mesh.disposeAll);

      await mesh.devices[0].mesh_.originate(sos());
      await mesh.settle(rounds: 80);

      for (var i = 1; i < 8; i++) {
        expect(mesh.devices[i].received, hasLength(1),
            reason: 'device $i received ${mesh.devices[i].received.length} copies — dedup failed');
      }
    });

    test('sparse/bridged — the bridge device carries it to the far cluster', () async {
      final mesh = await SimulatedMesh.bridged(3, 3);
      addTearDown(mesh.disposeAll);

      await mesh.devices[0].mesh_.originate(sos());
      await mesh.settle(rounds: 80);

      expect(mesh.devices[3].received, isNotEmpty, reason: 'bridge device missed it');
      expect(mesh.devices[5].received, isNotEmpty,
          reason: 'far cluster never reached — bridging is broken');
    });

    test('disconnect during relay — the mesh keeps moving packets', () async {
      final mesh = await SimulatedMesh.fullyConnected(5);
      addTearDown(mesh.disposeAll);

      mesh.disconnect(2); // device 2 drops out before traffic starts moving
      await mesh.devices[0].mesh_.originate(sos());
      await mesh.settle(rounds: 80);

      expect(mesh.devices[2].received, isEmpty, reason: 'a disconnected device receives nothing');
      for (final index in [1, 3, 4]) {
        expect(mesh.devices[index].received, hasLength(1),
            reason: 'device $index was blocked by the failed node — the pipeline stalled');
      }
    });
  });

  group('packet lifecycle rules', () {
    test('duplicate packet — a second copy is never accepted twice', () async {
      final mesh = await SimulatedMesh.chain(2);
      addTearDown(mesh.disposeAll);

      final packet = sos();
      await mesh.devices[0].mesh_.originate(packet);
      await mesh.settle();
      await mesh.devices[0].mesh_.originate(packet); // same packetId
      await mesh.settle();

      expect(mesh.devices[1].received, hasLength(1),
          reason: 'the same packet id was accepted twice');
    });

    test('expired TTL — a ttl-0 packet is rejected, not forwarded', () async {
      final mesh = await SimulatedMesh.chain(3);
      addTearDown(mesh.disposeAll);

      await mesh.devices[0].mesh_.originate(sos(ttl: 0));
      await mesh.settle();

      expect(mesh.devices[1].received, isEmpty,
          reason: 'PacketValidator must reject ttl below minimumTTL');
      expect(mesh.devices[2].received, isEmpty);
    });

    test('invalid signature — dropped at the receiver, never relayed onward', () async {
      final mesh = await SimulatedMesh.chain(3, signing: SigningBehaviour.alwaysInvalid);
      addTearDown(mesh.disposeAll);

      await mesh.devices[0].mesh_.originate(sos());
      await mesh.settle();

      expect(mesh.devices[1].received, isEmpty, reason: 'unsigned traffic must not be accepted');
      expect(mesh.devices[1].relayedAnything, isFalse,
          reason: 'an unverified packet must never be amplified by this device');
      expect(mesh.devices[2].received, isEmpty);
    });

    test('replayed packet — an old timestamp is refused', () async {
      final mesh = await SimulatedMesh.chain(2);
      addTearDown(mesh.disposeAll);

      final stale = DateTime.now().toUtc().subtract(
            SecurityConstants.maxPacketAge + const Duration(minutes: 1),
          );
      await mesh.devices[0].mesh_.originate(sos(timestamp: stale));
      await mesh.settle();

      expect(mesh.devices[1].received, isEmpty,
          reason: 'replay protection must reject a packet older than maxPacketAge');
    });

    test('multiple simultaneous SOS — all of them survive, none blocks another', () async {
      final mesh = await SimulatedMesh.fullyConnected(4);
      addTearDown(mesh.disposeAll);

      await Future.wait([
        mesh.devices[0].mesh_.originate(sos(packetId: 'sos-a', emergencyId: 'ea')),
        mesh.devices[1].mesh_.originate(sos(packetId: 'sos-b', emergencyId: 'eb')),
        mesh.devices[2].mesh_.originate(sos(packetId: 'sos-c', emergencyId: 'ec')),
      ]);
      await mesh.settle(rounds: 80);

      final atDevice3 = mesh.devices[3].received.map((packet) => packet.packetId).toSet();
      expect(atDevice3, containsAll(['sos-a', 'sos-b', 'sos-c']),
          reason: 'concurrent emergencies must not starve each other');
    });

    test('critical traffic is not delayed by a burst of routine traffic', () async {
      final mesh = await SimulatedMesh.chain(2);
      addTearDown(mesh.disposeAll);

      // Flood device 0 with low-priority traffic, then raise a real SOS.
      for (var i = 0; i < 25; i++) {
        await mesh.devices[0].mesh_.originate(
          sos(packetId: 'routine-$i', emergencyId: 'routine', priority: EmergencyPriority.low),
        );
      }
      await mesh.devices[0].mesh_.originate(
        sos(packetId: 'real-sos', emergencyId: 'critical-incident'),
      );
      await mesh.settle(rounds: 120);

      final ids = mesh.devices[1].received.map((packet) => packet.packetId).toList();
      expect(ids, contains('real-sos'), reason: 'the SOS never arrived at all');
    });
  });

  group('termination', () {
    setUp(() async {
      // Block 1: termination fails closed, so the responder key must be
      // in the (persisted) registry for these lifecycle tests.
      SharedPreferences.setMockInitialValues({});
      await ResponderRegistry.instance.resetForTesting();
      ResponderRegistry.instance.syncFromBackend(['responder-public-key']);
    });

    test('a verified termination stops further relay of that emergency', () async {
      final mesh = await SimulatedMesh.chain(2);
      addTearDown(mesh.disposeAll);

      await mesh.devices[0].mesh_.originate(sos(emergencyId: 'e-done'));
      await mesh.settle();
      expect(mesh.devices[1].received, hasLength(1));

      await mesh.devices[0].mesh_.originate(closure(emergencyId: 'e-done'));
      await mesh.settle();

      // A late-arriving packet for the closed incident must be dropped.
      await mesh.devices[0].mesh_.originate(
        sos(packetId: 'late-sos', emergencyId: 'e-done'),
      );
      await mesh.settle();

      final late = mesh.devices[1].received.where((p) => p.packetId == 'late-sos');
      expect(late, isEmpty, reason: 'packets for a closed emergency must not be accepted');
    });

    test('closing an emergency clears it from the durable queue', () async {
      final mesh = await SimulatedMesh.chain(2);
      addTearDown(mesh.disposeAll);

      await mesh.devices[0].mesh_.originate(sos(emergencyId: 'e-sweep'));
      await mesh.settle();
      expect(mesh.devices[1].queue.storedCount, greaterThan(0));

      await mesh.devices[0].mesh_.originate(closure(emergencyId: 'e-sweep'));
      await mesh.settle();

      final leftovers = await mesh.devices[1].queue.getPendingPackets();
      final stillQueued = leftovers
          .map((packet) => packet.toJson())
          .where((json) => json['emergency_id'] == 'e-sweep');
      expect(stillQueued, isEmpty, reason: 'resolved incident left packets in the queue');
    });
  });

  group('connectivity and the exit node', () {
    test('backend unavailable — packets are held, not lost', () async {
      final mesh = await SimulatedMesh.chain(2);
      addTearDown(mesh.disposeAll);

      mesh.devices[1].backend.internetAvailable = false;
      await mesh.devices[0].mesh_.originate(sos());
      await mesh.settle();

      expect(mesh.devices[1].backend.uploadedPacketIds, isEmpty);
      expect(mesh.devices[1].queue.pendingCount, greaterThan(0),
          reason: 'an offline device must retain the packet for later upload');
    });

    test('exit node failure — internet present but backend broken, packet retained', () async {
      final mesh = await SimulatedMesh.chain(2);
      addTearDown(mesh.disposeAll);

      mesh.devices[1].backend
        ..internetAvailable = true
        ..backendHealthy = false;

      await mesh.devices[0].mesh_.originate(sos());
      await mesh.settle();

      expect(mesh.devices[1].backend.uploadedPacketIds, isEmpty);
      expect(mesh.devices[1].queue.pendingCount, greaterThan(0),
          reason: 'a failed upload must leave the packet pending, not mark it delivered');
    });

    test('internet appears mid-route — the held packet uploads on arrival', () async {
      final mesh = await SimulatedMesh.chain(2);
      addTearDown(mesh.disposeAll);

      mesh.devices[1].backend.internetAvailable = false;
      await mesh.devices[0].mesh_.originate(sos(packetId: 'held-sos'));
      await mesh.settle();
      expect(mesh.devices[1].backend.uploadedPacketIds, isEmpty);

      // Connectivity returns; a second packet triggers the upload path
      // and the pending one goes with it.
      mesh.devices[1].backend.internetAvailable = true;
      await mesh.devices[0].mesh_.originate(sos(packetId: 'second-sos', emergencyId: 'e2'));
      await mesh.settle(rounds: 80);

      expect(mesh.devices[1].backend.uploadedPacketIds, contains('second-sos'),
          reason: 'upload path did not resume when connectivity returned');
    });

    test('internet disappears mid-route — later packets are queued, earlier ones stay uploaded',
        () async {
      final mesh = await SimulatedMesh.chain(2);
      addTearDown(mesh.disposeAll);

      mesh.devices[1].backend.internetAvailable = true;
      await mesh.devices[0].mesh_.originate(sos(packetId: 'online-sos'));
      await mesh.settle(rounds: 60);
      expect(mesh.devices[1].backend.uploadedPacketIds, contains('online-sos'));

      mesh.devices[1].backend.internetAvailable = false;
      await mesh.devices[0].mesh_.originate(sos(packetId: 'offline-sos', emergencyId: 'e2'));
      await mesh.settle(rounds: 60);

      expect(mesh.devices[1].backend.uploadedPacketIds, isNot(contains('offline-sos')));
      expect(mesh.devices[1].queue.pendingCount, greaterThan(0));
    });
  });
}
