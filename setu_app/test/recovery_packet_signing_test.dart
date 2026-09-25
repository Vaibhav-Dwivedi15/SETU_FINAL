// =====================================================
// SETU Project
// Module : Recovery report -> signed packet (real Ed25519)
// =====================================================
//
// Proves the Recovery flow rides the existing signed-packet transport and
// does not weaken it: the packet RecoveryPacketBuilder produces verifies
// with the sender's key, tampering with any signed field breaks it, and
// the mutable relay fields (ttl, hopCount) stay outside the signature.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setu_app/features/recovery/data/models/recovery_report_type.dart';
import 'package:setu_app/features/recovery/data/services/recovery_packet_builder.dart';
import 'package:setu_app/mesh/enums/emergency_priority.dart';
import 'package:setu_app/mesh/models/emergency_packet.dart';
import 'package:setu_app/mesh/models/packet_factory.dart';
import 'package:setu_app/mesh/services/signing_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Same in-memory stand-in for the Android Keystore as signing_service_test.
  final Map<String, String> secureStorage = {};
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  setUp(() {
    secureStorage.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      switch (call.method) {
        case 'write':
          final value = call.arguments['value'] as String?;
          value == null
              ? secureStorage.remove(call.arguments['key'] as String)
              : secureStorage[call.arguments['key'] as String] = value;
          return null;
        case 'read':
          return secureStorage[call.arguments['key'] as String];
        case 'delete':
          secureStorage.remove(call.arguments['key'] as String);
          return null;
        case 'readAll':
          return secureStorage;
        case 'containsKey':
          return secureStorage.containsKey(call.arguments['key'] as String);
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<(SigningService, EmergencyPacket)> build({
    RecoveryReportType type = RecoveryReportType.missingPerson,
    String message = 'Asha | age ~9 | last seen station | red jacket',
    EmergencyPriority priority = EmergencyPriority.high,
    SigningService? signing,
  }) async {
    final service = signing ?? SigningService();
    final packet = await RecoveryPacketBuilder(signingService: service).buildRecoveryPacket(
      type: type,
      latitude: 12.97,
      longitude: 77.59,
      message: message,
      priority: priority,
    );
    return (service, packet);
  }

  Future<bool> verifies(SigningService s, EmergencyPacket p) =>
      s.verify(p.signaturePayload, p.senderId, p.signature);

  test('the built packet carries a valid Ed25519 signature from the sender key', () async {
    final (service, packet) = await build();
    expect(packet.signature, isNotEmpty);
    expect(packet.senderId, await service.getOrCreatePublicKeyHex());
    expect(await verifies(service, packet), isTrue);
  });

  test('it is an ordinary EmergencyPacket: prefixed message, emergencyId == packetId',
      () async {
    final (_, packet) = await build(type: RecoveryReportType.damage, message: 'Road | High');
    expect(packet.message, '[RECOVERY:DAMAGE] Road | High');
    expect(packet.emergencyId, packet.packetId);
    expect(packet.priority, EmergencyPriority.high);
    expect(packet.type.name, 'emergency');
    expect(packet.hopCount, 0);
    expect(packet.ttl, greaterThan(0));
  });

  test('relay-mutable fields are outside the signature: ttl / hopCount can change', () async {
    final (service, packet) = await build();
    final relayed = packet.copyWith(ttl: packet.ttl - 3, hopCount: packet.hopCount + 3);
    expect(relayed.signaturePayload, packet.signaturePayload);
    expect(await verifies(service, relayed), isTrue);
  });

  test('every signed field is protected: tampering breaks verification', () async {
    final (service, packet) = await build();
    final tampered = <String, EmergencyPacket>{
      'message': packet.copyWith(message: '${packet.message} (edited)'),
      'priority': packet.copyWith(priority: EmergencyPriority.low),
      'latitude': packet.copyWith(latitude: packet.latitude + 0.5),
      'longitude': packet.copyWith(longitude: packet.longitude + 0.5),
      'emergencyId': packet.copyWith(emergencyId: 'someone-elses-emergency'),
      'nonce': packet.copyWith(nonce: 'different-nonce'),
      'timestamp': packet.copyWith(timestamp: packet.timestamp.add(const Duration(minutes: 1))),
      'packetId': packet.copyWith(packetId: 'other-packet-id'),
    };
    for (final entry in tampered.entries) {
      expect(await verifies(service, entry.value), isFalse,
          reason: 'changing ${entry.key} must invalidate the signature');
    }
  });

  test('the signature does not verify under another sender key, and a forged one fails',
      () async {
    final (service, packet) = await build();
    secureStorage.clear();
    final strangerKey = await SigningService().getOrCreatePublicKeyHex();
    expect(strangerKey, isNot(packet.senderId));

    // Claiming the report came from someone else must fail.
    expect(await service.verify(packet.signaturePayload, strangerKey, packet.signature), isFalse);
    // So must a made-up signature under the real sender key.
    expect(await service.verify(packet.signaturePayload, packet.senderId, '00' * 64), isFalse);
  });

  test('every dispatch is a fresh packet: unique id and nonce, so nothing is replayed',
      () async {
    final service = SigningService();
    final (_, first) = await build(signing: service);
    final (_, second) = await build(signing: service);
    expect(second.packetId, isNot(first.packetId));
    expect(second.nonce, isNot(first.nonce));
    expect(second.emergencyId, isNot(first.emergencyId));
    expect(second.signature, isNot(first.signature));
    expect(await verifies(service, first), isTrue);
    expect(await verifies(service, second), isTrue);
  });

  test('the wire round trip (toJson -> fromJson) preserves a verifiable signature', () async {
    final (service, packet) = await build();
    final decoded = PacketFactory.fromJson(packet.toJson()) as EmergencyPacket;
    expect(decoded.message, packet.message);
    expect(await verifies(service, decoded), isTrue);
  });

  test('the packet is well inside the transport size limit even at the message cap',
      () async {
    final (_, packet) = await build(message: 'x' * 480);
    expect(packet.toJson().toString().length, lessThan(4096));
  });
}
