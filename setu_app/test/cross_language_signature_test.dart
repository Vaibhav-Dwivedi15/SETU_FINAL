import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setu_app/mesh/enums/emergency_priority.dart';
import 'package:setu_app/mesh/models/ack_packet.dart';
import 'package:setu_app/mesh/models/alert_packet.dart';
import 'package:setu_app/mesh/models/emergency_packet.dart';
import 'package:setu_app/mesh/models/mesh_packet.dart';
import 'package:setu_app/mesh/models/packet_factory.dart';
import 'package:setu_app/mesh/models/termination_packet.dart';
import 'package:setu_app/mesh/services/signing_service.dart';

/// Cross-language signature vector, DART side (BLOCK 1, Phase 16).
///
/// Signs packets with the REAL production stack -- SigningService (real
/// Ed25519 from a fixed seed), the real packet models' signaturePayload,
/// and the real wire encoding `jsonEncode(packet.toJson())` -- then
/// checks, in Dart, that the genuine packets verify and every tampered
/// variant fails.
///
/// When SETU_XLANG_OUT=<dir> is set it also writes each wire packet to
/// <dir>/<name>.json plus <dir>/manifest.tsv ("name<TAB>expected"), which
/// the Kotlin JUnit test (CrossLanguageVectorTest) and the Python script
/// (tools/cross_lang/verify_python.py) consume. Kotlin and Python are
/// therefore verifying exactly what Dart signed, byte for byte on the wire.
///
/// Only the platform secure-storage channel is mocked (as in
/// signing_service_test.dart); the signing itself is not.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  // Fixed test seed 0x00..0x1f -- a fixture, not a production key.
  final seedHex = List.generate(32, (i) => i.toRadixString(16).padLeft(2, '0')).join();
  final store = <String, String>{'setu_signing_private_key_seed': seedHex};

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'read':
          return store[call.arguments['key']];
        case 'write':
          store[call.arguments['key'] as String] = call.arguments['value'] as String;
          return null;
        case 'containsKey':
          return store.containsKey(call.arguments['key']);
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('Dart signs; genuine packets verify; every tampered variant fails; fixtures exported', () async {
    final signing = SigningService();
    final sender = await signing.getOrCreatePublicKeyHex();
    expect(sender, hasLength(64));

    final ts = DateTime.utc(2026, 9, 24, 10, 30, 15, 123, 456); // microseconds -> 6-digit fraction
    Future<T> sign<T extends MeshPacket>(T unsigned, T Function(String) withSignature) async =>
        withSignature(await signing.sign(unsigned.signaturePayload));

    final emergency = await sign(
      EmergencyPacket(
        packetId: '${sender.substring(0, 8)}-1790245815123456',
        senderId: sender,
        timestamp: ts,
        nonce: '000102030405060708090a0b0c0d0e0f',
        ttl: 5,
        hopCount: 0,
        signature: '',
        emergencyId: '${sender.substring(0, 8)}-1790245815123456',
        latitude: 25.4358011,
        longitude: 81.8463302,
        // Pipes, unicode and quotes in the message: the delimiter and
        // encoding edge cases that could diverge between languages.
        message: 'Trapped | बचाओ "help" 火',
        priority: EmergencyPriority.critical,
      ),
      (s) => EmergencyPacket(
        packetId: '${sender.substring(0, 8)}-1790245815123456',
        senderId: sender,
        timestamp: ts,
        nonce: '000102030405060708090a0b0c0d0e0f',
        ttl: 5,
        hopCount: 0,
        signature: s,
        emergencyId: '${sender.substring(0, 8)}-1790245815123456',
        latitude: 25.4358011,
        longitude: 81.8463302,
        message: 'Trapped | बचाओ "help" 火',
        priority: EmergencyPriority.critical,
      ),
    );

    // Whole-degree and negative coordinates: "28.0" / "-33.8688" formatting.
    final emergency2 = await sign(
      EmergencyPacket(
        packetId: 'wholedeg-1',
        senderId: sender,
        timestamp: DateTime.utc(2026, 9, 24, 10, 30, 15),
        nonce: 'aa' * 16,
        ttl: 4,
        hopCount: 1,
        signature: '',
        emergencyId: 'wholedeg-1',
        latitude: 28.0,
        longitude: -77.0,
        message: 'plain',
        priority: EmergencyPriority.low,
      ),
      (s) => EmergencyPacket(
        packetId: 'wholedeg-1',
        senderId: sender,
        timestamp: DateTime.utc(2026, 9, 24, 10, 30, 15),
        nonce: 'aa' * 16,
        ttl: 4,
        hopCount: 1,
        signature: s,
        emergencyId: 'wholedeg-1',
        latitude: 28.0,
        longitude: -77.0,
        message: 'plain',
        priority: EmergencyPriority.low,
      ),
    );

    final ack = await sign(
      AckPacket(
        packetId: 'ack-1',
        senderId: sender,
        timestamp: ts,
        nonce: 'bb' * 16,
        ttl: 5,
        hopCount: 0,
        signature: '',
        originalPacketId: 'orig-1',
        emergencyId: 'em-1',
      ),
      (s) => AckPacket(
        packetId: 'ack-1',
        senderId: sender,
        timestamp: ts,
        nonce: 'bb' * 16,
        ttl: 5,
        hopCount: 0,
        signature: s,
        originalPacketId: 'orig-1',
        emergencyId: 'em-1',
      ),
    );

    final termination = await sign(
      TerminationPacket(
        packetId: 'term-1',
        senderId: sender,
        timestamp: ts,
        nonce: 'cc' * 16,
        ttl: 5,
        hopCount: 0,
        signature: '',
        emergencyId: 'em-1',
        responderId: 'badge-7',
      ),
      (s) => TerminationPacket(
        packetId: 'term-1',
        senderId: sender,
        timestamp: ts,
        nonce: 'cc' * 16,
        ttl: 5,
        hopCount: 0,
        signature: s,
        emergencyId: 'em-1',
        responderId: 'badge-7',
      ),
    );

    final alert = await sign(
      AlertPacket(
        packetId: 'alert-1',
        senderId: sender,
        timestamp: ts,
        nonce: 'dd' * 16,
        ttl: 5,
        hopCount: 0,
        signature: '',
        incidentType: 'fire',
        latitude: 12.9716,
        longitude: 77.5946,
        radiusMeters: 1000,
      ),
      (s) => AlertPacket(
        packetId: 'alert-1',
        senderId: sender,
        timestamp: ts,
        nonce: 'dd' * 16,
        ttl: 5,
        hopCount: 0,
        signature: s,
        incidentType: 'fire',
        latitude: 12.9716,
        longitude: 77.5946,
        radiusMeters: 1000,
      ),
    );

    // name -> wire bytes exactly as MeshServiceImpl.originate() encodes them
    final genuine = <String, MeshPacket>{
      'emergency': emergency,
      'emergency_wholedeg': emergency2,
      'ack': ack,
      'termination': termination,
      'alert': alert,
    };
    final wire = <String, String>{};
    final expected = <String, bool>{};

    for (final entry in genuine.entries) {
      final json = jsonEncode(entry.value.toJson());
      wire[entry.key] = json;
      expected[entry.key] = true;
      // Dart verifies what it just signed, through the wire round trip.
      final back = PacketFactory.fromJson(jsonDecode(json) as Map<String, dynamic>);
      expect(await signing.verify(back.signaturePayload, back.senderId, back.signature), isTrue,
          reason: '${entry.key} must verify in Dart');
    }

    // ---- tampering, applied to the emergency packet's wire JSON ----
    final base = jsonDecode(wire['emergency']!) as Map<String, dynamic>;
    String flipHex(String s) => (s[0] == '0' ? '1' : '0') + s.substring(1);
    final otherSender = 'ff${sender.substring(2)}';
    final tampers = <String, void Function(Map<String, dynamic>)>{
      'tamper_message': (m) => m['message'] = 'Trapped | बचाओ "help" 火!',
      'tamper_timestamp': (m) => m['timestamp'] = '2026-09-24T10:30:16.123456Z',
      'tamper_latitude': (m) => m['latitude'] = 25.4358012,
      'tamper_longitude': (m) => m['longitude'] = 81.8463303,
      'tamper_sender_id': (m) => m['sender_id'] = otherSender,
      'tamper_signature': (m) => m['signature'] = flipHex(m['signature'] as String),
      'tamper_priority': (m) => m['priority'] = 'low',
      'tamper_nonce': (m) => m['nonce'] = 'ff' * 16,
      'tamper_packet_id': (m) => m['packet_id'] = 'other-id',
      'tamper_emergency_id': (m) => m['emergency_id'] = 'other-em',
    };
    for (final entry in tampers.entries) {
      final m = Map<String, dynamic>.from(base);
      entry.value(m);
      final json = jsonEncode(m);
      wire[entry.key] = json;
      expected[entry.key] = false;
      final back = PacketFactory.fromJson(jsonDecode(json) as Map<String, dynamic>);
      expect(await signing.verify(back.signaturePayload, back.senderId, back.signature), isFalse,
          reason: '${entry.key} must FAIL in Dart');
    }

    // ttl / hop_count are deliberately unsigned: changing them must NOT
    // break verification (relays rewrite them).
    final relayed = Map<String, dynamic>.from(base)
      ..['ttl'] = 3
      ..['hop_count'] = 2;
    wire['relay_rewrites_ttl_hop'] = jsonEncode(relayed);
    expected['relay_rewrites_ttl_hop'] = true;
    final relayedBack = PacketFactory.fromJson(relayed);
    expect(await signing.verify(relayedBack.signaturePayload, relayedBack.senderId, relayedBack.signature),
        isTrue);

    final outDir = Platform.environment['SETU_XLANG_OUT'];
    if (outDir != null && outDir.isNotEmpty) {
      final dir = Directory(outDir)..createSync(recursive: true);
      final manifest = StringBuffer();
      for (final name in wire.keys) {
        File('${dir.path}/$name.json').writeAsStringSync(wire[name]!, encoding: utf8);
        manifest.writeln('$name\t${expected[name]}');
      }
      File('${dir.path}/manifest.tsv').writeAsStringSync(manifest.toString());
    }
  });
}
