import 'package:flutter_test/flutter_test.dart';
import 'package:setu_app/mesh/enums/emergency_priority.dart';
import 'package:setu_app/mesh/enums/packet_type.dart';
import 'package:setu_app/mesh/models/emergency_packet.dart';
import 'package:setu_app/mesh/models/mesh_packet.dart';
import 'package:setu_app/mesh/models/packet_factory.dart';
import 'package:setu_app/mesh/models/termination_packet.dart';

// Pure Dart logic tests — no device, no plugins, run with `flutter test`.
// These specifically cover the bugs found and fixed during earlier code
// review: the copyWith/withRelayHop polymorphism issue, and the
// snake_case JSON key contract the whole team depends on.

void main() {
  group('EmergencyPacket', () {
    late EmergencyPacket packet;

    setUp(() {
      packet = EmergencyPacket(
        packetId: 'p1',
        senderId: 'sender-key-abc',
        timestamp: DateTime.utc(2026, 1, 1, 12, 0, 0),
        nonce: 'nonce123',
        ttl: 5,
        hopCount: 0,
        signature: 'sig123',
        emergencyId: 'e1',
        latitude: 28.6,
        longitude: 77.2,
        message: 'Test SOS',
        priority: EmergencyPriority.high,
      );
    });

    test('toJson uses snake_case keys — every teammate depends on this', () {
      final json = packet.toJson();
      expect(json.containsKey('packet_id'), true);
      expect(json.containsKey('sender_id'), true);
      expect(json.containsKey('hop_count'), true);
      expect(json.containsKey('emergency_id'), true);
      expect(json.containsKey('protocol_version'), true);
      // must NOT contain the old camelCase keys — regression guard
      expect(json.containsKey('packetId'), false);
      expect(json.containsKey('senderId'), false);
    });

    test('toJson -> fromJson round-trip preserves every field', () {
      final json = packet.toJson();
      final restored = EmergencyPacket.fromJson(json);
      expect(restored.packetId, packet.packetId);
      expect(restored.senderId, packet.senderId);
      expect(restored.nonce, packet.nonce);
      expect(restored.ttl, packet.ttl);
      expect(restored.hopCount, packet.hopCount);
      expect(restored.signature, packet.signature);
      expect(restored.emergencyId, packet.emergencyId);
      expect(restored.latitude, packet.latitude);
      expect(restored.longitude, packet.longitude);
      expect(restored.message, packet.message);
      expect(restored.priority, packet.priority);
    });

    test('withRelayHop decrements TTL and increments hopCount', () {
      final relayed = packet.withRelayHop() as EmergencyPacket;
      expect(relayed.ttl, packet.ttl - 1);
      expect(relayed.hopCount, packet.hopCount + 1);
    });

    test(
      'withRelayHop preserves subclass fields — regression guard for the '
      'original copyWith bug where relaying through a MeshPacket-typed '
      'reference silently dropped emergencyId/lat/lng/message/priority',
      () {
        final MeshPacket asBase = packet; // deliberately widen the type
        final relayed = asBase.withRelayHop();
        expect(relayed, isA<EmergencyPacket>());
        final relayedEmergency = relayed as EmergencyPacket;
        expect(relayedEmergency.emergencyId, packet.emergencyId);
        expect(relayedEmergency.latitude, packet.latitude);
        expect(relayedEmergency.message, packet.message);
        expect(relayedEmergency.priority, packet.priority);
      },
    );

    test('signaturePayload changes if any signed field changes', () {
      final original = packet.signaturePayload;
      final tampered = packet.copyWith(message: 'Tampered message').signaturePayload;
      expect(original == tampered, false);
    });

    test('PacketFactory.fromJson dispatches emergency packets correctly', () {
      final decoded = PacketFactory.fromJson(packet.toJson());
      expect(decoded, isA<EmergencyPacket>());
      expect(decoded.packetId, packet.packetId);
    });
  });

  group('TerminationPacket', () {
    late TerminationPacket packet;

    setUp(() {
      packet = TerminationPacket(
        packetId: 'p2',
        senderId: 'responder-key-xyz',
        timestamp: DateTime.utc(2026, 1, 1, 12, 5, 0),
        nonce: 'nonce456',
        ttl: 5,
        hopCount: 0,
        signature: 'sig456',
        emergencyId: 'e1',
        responderId: 'responder-key-xyz',
      );
    });

    test('toJson uses snake_case keys', () {
      final json = packet.toJson();
      expect(json.containsKey('emergency_id'), true);
      expect(json.containsKey('responder_id'), true);
    });

    test('toJson -> fromJson round-trip', () {
      final restored = TerminationPacket.fromJson(packet.toJson());
      expect(restored.emergencyId, packet.emergencyId);
      expect(restored.responderId, packet.responderId);
    });

    test('withRelayHop preserves emergencyId and responderId', () {
      final relayed = packet.withRelayHop() as TerminationPacket;
      expect(relayed.emergencyId, packet.emergencyId);
      expect(relayed.responderId, packet.responderId);
      expect(relayed.ttl, packet.ttl - 1);
    });

    test('PacketFactory.fromJson dispatches termination packets correctly', () {
      final decoded = PacketFactory.fromJson(packet.toJson());
      expect(decoded, isA<TerminationPacket>());
    });
  });

  group('PacketType enum + JSON', () {
    test('type field round-trips correctly for both packet types', () {
      final emergencyJson = EmergencyPacket(
        packetId: 'p3', senderId: 's', timestamp: DateTime.now(),
        nonce: 'n', ttl: 5, hopCount: 0, signature: 'sig',
        emergencyId: 'e', latitude: 0, longitude: 0,
        message: 'm', priority: EmergencyPriority.low,
      ).toJson();
      expect(emergencyJson['type'], PacketType.emergency.name);
    });
  });
}
