import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:typed_data';

import '../../security/packet_validator.dart';
import '../../security/security_constants.dart';
import '../../security/security_exceptions.dart';
import '../../services/backend_service.dart';
import '../../services/power_mode.dart';
import '../../services/power_mode_controller.dart';
import '../../features/sos/data/services/ack_packet_builder.dart';
import '../../features/relay/data/models/relay_log_entry.dart';
import '../../features/relay/data/repositories/relay_log_repository.dart';
import '../models/ack_packet.dart';
import '../models/alert_packet.dart';
import '../models/emergency_packet.dart';
import '../models/mesh_packet.dart';
import '../models/packet_factory.dart';
import '../models/termination_packet.dart';
import 'local_queue_service.dart';
import 'mesh_metrics.dart';
import 'mesh_policy.dart';
import 'nearby_service.dart';
import 'responder_registry.dart';
import 'signing_service.dart';

abstract class MeshService {
  Future<void> originate(MeshPacket packet);
  Stream<MeshPacket> get incomingPackets;
  Stream<AckPacket> get acknowledgments;
  void dispose();
}

class MeshServiceImpl implements MeshService {
  MeshServiceImpl({
    required NearbyService nearbyService,
    required SigningService signingService,
    required BackendService backendService,
    required LocalQueueService queueService,
  })  : _nearby = nearbyService,
        _signing = signingService,
        _backend = backendService,
        _queue = queueService {
    _subscription = _nearby.events.listen(_handleNearbyEvent);
    _retryTimer = Timer.periodic(const Duration(seconds: 30), (_) => _retryPendingUploads());
    _registryTimer = Timer.periodic(const Duration(minutes: 5), (_) => _syncResponderRegistry());
    unawaited(PowerModeController.instance.initialize());
    _policySub = PowerModeController.instance.stream.listen((mode) {
      _currentPolicy = MeshPolicy.fromPowerMode(mode);
      developer.log('Power mode changed -> ${mode.name}', name: 'MeshService');
      unawaited(_pushPolicyToNative());
    });
    _currentPolicy = MeshPolicy.fromPowerMode(PowerModeController.instance.currentMode);
    unawaited(_pushPolicyToNative());
    unawaited(_retryPendingUploads());
    unawaited(_syncResponderRegistry());
  }

  final NearbyService _nearby;
  final SigningService _signing;
  final BackendService _backend;
  final LocalQueueService _queue;
  final PacketValidator _validator = PacketValidator();
  final _incomingController = StreamController<MeshPacket>.broadcast();
  final Set<String> _closedEmergencyIds = {};

  final AckPacketBuilder _ackBuilder = AckPacketBuilder();
  final Set<String> _originatedEmergencyIds = {};
  final _acknowledgmentsController = StreamController<AckPacket>.broadcast();
  late final StreamSubscription<NearbyEvent> _subscription;
  late final StreamSubscription<PowerMode> _policySub;
  late final Timer _retryTimer;
  late final Timer _registryTimer;
  MeshPolicy _currentPolicy = MeshPolicy.fromPowerMode(PowerMode.full);

  @override
  Stream<MeshPacket> get incomingPackets => _incomingController.stream;

  @override
  Stream<AckPacket> get acknowledgments => _acknowledgmentsController.stream;

  Future<void> _pushPolicyToNative() async {
    try {
      await _nearby.updatePolicy(
        scanInterval: _currentPolicy.scanInterval,
        discoveryInterval: _currentPolicy.discoveryInterval,
        allowRelay: _currentPolicy.allowRelay,
      );
      developer.log(
        'Pushed mesh policy to native: scan=${_currentPolicy.scanInterval} discovery=${_currentPolicy.discoveryInterval} allowRelay=${_currentPolicy.allowRelay}',
        name: 'MeshService',
      );
    } catch (e) {
      developer.log('Failed to push mesh policy to native: $e', name: 'MeshService');
    }
  }

  @override
  Future<void> originate(MeshPacket packet) async {
    developer.log(
      'Originating packet: ${packet.packetId} type=${packet.type} ttl=${packet.ttl} sender=${packet.senderId.substring(0, 8)}...',
      name: 'MeshService',
    );
    if (packet is EmergencyPacket) {
      _originatedEmergencyIds.add(packet.emergencyId);
    }

    await _queue.enqueue(packet);
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(packet.toJson())));
    await _nearby.originate(bytes, packet.packetId);
    developer.log('Packet handed to NearbyService.originate: ${packet.packetId} (${bytes.length} bytes)', name: 'MeshService');
    MeshMetrics.instance.sent++;
    MeshMetrics.instance.notify();
    // Aug 6 2026: persistent relay log entry -- see RelayLogRepository
    // for why (MeshMetrics alone resets to 0 on every app restart).
    unawaited(RelayLogRepository.instance.log(
      type: RelayLogType.sent,
      packetId: packet.packetId,
      detail: '${packet.type.name} packet originated',
    ));
    _tryUpload(packet);
  }

  void _handleNearbyEvent(NearbyEvent event) {
    switch (event) {
      case PeerConnected():
        developer.log('Peer connected: ${event.endpointId}', name: 'MeshService');
      case PeerDisconnected():
        developer.log('Peer disconnected: ${event.endpointId}', name: 'MeshService');
      case PayloadReceived():
        developer.log('Raw payload received: ${event.bytes.length} bytes', name: 'MeshService');
        _handlePayload(event.bytes);
    }
  }

  Future<void> _handlePayload(Uint8List bytes) async {
    final MeshPacket packet;
    try {
      final jsonMap = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      packet = PacketFactory.fromJson(jsonMap);
    } catch (e) {
      developer.log('Dropped malformed packet: $e', name: 'MeshService');
      MeshMetrics.instance.dropped++;
      MeshMetrics.instance.notify();
      unawaited(RelayLogRepository.instance.log(
        type: RelayLogType.dropped,
        packetId: 'unknown',
        detail: 'Malformed payload',
      ));
      return;
    }

    developer.log(
      'Decoded packet: ${packet.packetId} type=${packet.type} ttl=${packet.ttl} hop=${packet.hopCount} sender=${packet.senderId.substring(0, 8)}...',
      name: 'MeshService',
    );

    try {
      _validator.validate(
        packetVersion: packet.protocolVersion,
        ttl: packet.ttl,
        timestamp: packet.timestamp,
        nonce: packet.nonce,
      );
    } on SecurityException catch (e) {
      developer.log('Dropped packet failing security validation: $e (${packet.packetId})', name: 'MeshService');
      MeshMetrics.instance.dropped++;
      MeshMetrics.instance.notify();
      unawaited(RelayLogRepository.instance.log(
        type: RelayLogType.dropped,
        packetId: packet.packetId,
        detail: 'Failed security validation',
      ));
      return;
    }
    developer.log('Packet passed PacketValidator: ${packet.packetId}', name: 'MeshService');

    final isValid = await _signing.verify(packet.signaturePayload, packet.senderId, packet.signature);
    if (!isValid) {
      developer.log('Dropped packet with invalid signature: ${packet.packetId}', name: 'MeshService');
      MeshMetrics.instance.dropped++;
      MeshMetrics.instance.notify();
      unawaited(RelayLogRepository.instance.log(
        type: RelayLogType.dropped,
        packetId: packet.packetId,
        detail: 'Invalid signature',
      ));
      return;
    }
    developer.log('Packet signature VERIFIED: ${packet.packetId}', name: 'MeshService');

    if (packet is TerminationPacket) {
      final (authorized, enforced) = ResponderRegistry.instance.checkResponder(packet.senderId);
      if (!authorized) {
        developer.log('Dropped termination from unauthorized responder: ${packet.senderId}', name: 'MeshService');
        MeshMetrics.instance.dropped++;
        MeshMetrics.instance.notify();
        unawaited(RelayLogRepository.instance.log(
          type: RelayLogType.dropped,
          packetId: packet.packetId,
          detail: 'Unauthorized termination',
        ));
        return;
      }
      if (!enforced) {
        developer.log('WARNING: termination accepted without registry enforcement (no backend sync yet)', name: 'MeshService');
      }
      _closedEmergencyIds.add(packet.emergencyId);
      await _queue.markEmergencyClosed(packet.emergencyId);
      developer.log('Emergency ${packet.emergencyId} marked CLOSED', name: 'MeshService');
    }

    if (packet is EmergencyPacket && _closedEmergencyIds.contains(packet.emergencyId)) {
      developer.log('Dropped packet for closed emergency: ${packet.emergencyId}', name: 'MeshService');
      MeshMetrics.instance.dropped++;
      MeshMetrics.instance.notify();
      unawaited(RelayLogRepository.instance.log(
        type: RelayLogType.dropped,
        packetId: packet.packetId,
        detail: 'Emergency already closed',
      ));
      return;
    }

    MeshMetrics.instance.received++;
    MeshMetrics.instance.notify();
    unawaited(RelayLogRepository.instance.log(
      type: RelayLogType.received,
      packetId: packet.packetId,
      detail: '${packet.type.name} packet, hop ${packet.hopCount}',
    ));
    await _queue.enqueue(packet);
    _incomingController.add(packet);
    developer.log('Packet ACCEPTED and queued: ${packet.packetId} (total received=${MeshMetrics.instance.received})', name: 'MeshService');

    _relayPacket(packet);

    if (packet is AckPacket) {
      if (_originatedEmergencyIds.contains(packet.emergencyId)) {
        developer.log('Ack received for own emergency: ${packet.emergencyId}', name: 'MeshService');
        _acknowledgmentsController.add(packet);
      }
      return;
    }
    if (packet is AlertPacket) {
      return;
    }

    if (!_currentPolicy.allowUpload) {
      developer.log('Upload skipped — power saver mode active', name: 'MeshService');
      return;
    }
    _tryUpload(packet);
  }

  void _relayPacket(MeshPacket packet) {
    if (!_currentPolicy.allowRelay) {
      developer.log(
        'Relay skipped — power saver mode active (battery-aware guard): ${packet.packetId}',
        name: 'MeshService',
      );
      return;
    }

    final MeshPacket relayed;
    try {
      relayed = packet.withRelayHop();
    } catch (e) {
      developer.log('Failed to build relay hop for ${packet.packetId}: $e', name: 'MeshService');
      return;
    }

    if (relayed.ttl < SecurityConstants.minimumTTL) {
      developer.log('Not relaying further — TTL exhausted: ${packet.packetId}', name: 'MeshService');
      return;
    }

    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(relayed.toJson())));
    unawaited(_nearby.originate(bytes, relayed.packetId));
    developer.log(
      'Relayed packet to next hop: ${relayed.packetId} ttl=${relayed.ttl} hop=${relayed.hopCount}',
      name: 'MeshService',
    );
    MeshMetrics.instance.relayed++;
    MeshMetrics.instance.notify();
    unawaited(RelayLogRepository.instance.log(
      type: RelayLogType.relayed,
      packetId: relayed.packetId,
      detail: 'Carried forward, now hop ${relayed.hopCount}',
    ));
  }

  void _tryUpload(MeshPacket packet) {
    if (packet is AckPacket || packet is AlertPacket) return;

    unawaited(() async {
      final online = await _backend.hasRealInternet();
      if (!online) return;
      final ok = await _backend.uploadPacket(packet);
      if (ok) {
        await _queue.markUploaded(packet.packetId);
        MeshMetrics.instance.uploaded++;
        MeshMetrics.instance.notify();
        unawaited(RelayLogRepository.instance.log(
          type: RelayLogType.uploaded,
          packetId: packet.packetId,
          detail: 'Delivered to backend',
        ));
        if (packet is EmergencyPacket) {
          unawaited(_originateAck(packet));
        }
      }
    }());
  }

  Future<void> _originateAck(EmergencyPacket packet) async {
    try {
      final ack = await _ackBuilder.buildAckPacket(
        originalPacketId: packet.packetId,
        emergencyId: packet.emergencyId,
      );
      await originate(ack);
      developer.log('Ack originated for emergency: ${packet.emergencyId}', name: 'MeshService');
    } catch (e) {
      developer.log('Failed to originate ack for ${packet.emergencyId}: $e', name: 'MeshService');
    }
  }

  Future<void> _syncResponderRegistry() async {
    final online = await _backend.hasRealInternet();
    if (!online) return;

    final keys = await _backend.fetchResponderKeys();
    if (keys == null) {
      developer.log('Responder registry sync skipped — fetch failed', name: 'MeshService');
      return;
    }

    ResponderRegistry.instance.syncFromBackend(keys);
    developer.log(
      'Responder registry synced: ${keys.length} trusted responder key(s)',
      name: 'MeshService',
    );
  }

  Future<void> _retryPendingUploads() async {
    if (!_currentPolicy.allowUpload) return;
    final online = await _backend.hasRealInternet();
    if (!online) return;

    final pending = await _queue.getPendingPackets();
    for (final packet in pending) {
      final ok = await _backend.uploadPacket(packet);
      if (ok) {
        await _queue.markUploaded(packet.packetId);
        MeshMetrics.instance.uploaded++;
        MeshMetrics.instance.notify();
        unawaited(RelayLogRepository.instance.log(
          type: RelayLogType.uploaded,
          packetId: packet.packetId,
          detail: 'Delivered to backend (retry)',
        ));
      }
    }
  }

  @override
  void dispose() {
    _subscription.cancel();
    _policySub.cancel();
    _retryTimer.cancel();
    _registryTimer.cancel();
    _acknowledgmentsController.close();
    PowerModeController.instance.dispose();
  }
}
