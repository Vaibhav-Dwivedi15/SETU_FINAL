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
    unawaited(PowerModeController.instance.initialize());
    _policySub = PowerModeController.instance.stream.listen((mode) {
      _currentPolicy = MeshPolicy.fromPowerMode(mode);
      developer.log('Power mode changed -> ${mode.name}', name: 'MeshService');
    });
    _currentPolicy = MeshPolicy.fromPowerMode(PowerModeController.instance.currentMode);
    unawaited(_retryPendingUploads());
  }

  final NearbyService _nearby;
  final SigningService _signing;
  final BackendService _backend;
  final LocalQueueService _queue;
  final PacketValidator _validator = PacketValidator(); // Security Lead's module
  final _incomingController = StreamController<MeshPacket>.broadcast();
  final Set<String> _closedEmergencyIds = {};
  late final StreamSubscription<NearbyEvent> _subscription;
  late final StreamSubscription<PowerMode> _policySub;
  late final Timer _retryTimer;
  MeshPolicy _currentPolicy = MeshPolicy.fromPowerMode(PowerMode.full);

  @override
  Stream<MeshPacket> get incomingPackets => _incomingController.stream;

  @override
  Future<void> originate(MeshPacket packet) async {
    // Not run through PacketValidator: replay/timestamp protection exists
    // to catch packets ARRIVING from the mesh, not ones this device just
    // created itself (a fresh packet's own nonce/timestamp always passes
    // trivially — validating it here would be redundant, not incorrect).
    developer.log(
      'Originating packet: ${packet.packetId} type=${packet.type} ttl=${packet.ttl} sender=${packet.senderId.substring(0, 8)}...',
      name: 'MeshService',
    );
    await _queue.enqueue(packet);
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(packet.toJson())));
    await _nearby.originate(bytes, packet.packetId);
    developer.log('Packet handed to NearbyService.originate: ${packet.packetId} (${bytes.length} bytes)', name: 'MeshService');
    MeshMetrics.instance.sent++;
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
      return;
    }

    developer.log(
      'Decoded packet: ${packet.packetId} type=${packet.type} ttl=${packet.ttl} hop=${packet.hopCount} sender=${packet.senderId.substring(0, 8)}...',
      name: 'MeshService',
    );

    // Security Lead's validator: packet version, TTL bounds, timestamp
    // freshness, and nonce replay — checked ONCE, here, at the moment a
    // packet is first received off the mesh. Deliberately NOT re-run when
    // a queued packet is later uploaded to the backend (see
    // _retryPendingUploads) — store-and-forward can legitimately hold a
    // packet for a while before an exit node gets internet, and re-running
    // a 5-minute freshness check at upload time would reject perfectly
    // valid delayed packets. One validation at intake is the right point.
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
      return;
    }
    developer.log('Packet passed PacketValidator: ${packet.packetId}', name: 'MeshService');

    final isValid = await _signing.verify(packet.signaturePayload, packet.senderId, packet.signature);
    if (!isValid) {
      developer.log('Dropped packet with invalid signature: ${packet.packetId}', name: 'MeshService');
      MeshMetrics.instance.dropped++;
      return;
    }
    developer.log('Packet signature VERIFIED: ${packet.packetId}', name: 'MeshService');

    if (packet is TerminationPacket) {
      final (authorized, enforced) = ResponderRegistry.instance.checkResponder(packet.senderId);
      if (!authorized) {
        developer.log('Dropped termination from unauthorized responder: ${packet.senderId}', name: 'MeshService');
        MeshMetrics.instance.dropped++;
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
      return;
    }

    MeshMetrics.instance.received++;
    await _queue.enqueue(packet);
    _incomingController.add(packet);
    developer.log('Packet ACCEPTED and queued: ${packet.packetId} (total received=${MeshMetrics.instance.received})', name: 'MeshService');

    // FIX (previously missing): forward this packet to the next hop.
    // Before this, an accepted packet was only queued/uploaded locally —
    // it never got re-broadcast, so anything past a direct A->B hop
    // (i.e. real multi-hop relay through a middle device) could not
    // actually work. withRelayHop() decrements TTL, increments hop_count,
    // and preserves subclass fields (emergency_id, lat/lng, message,
    // priority / responder_id) — covered by the existing packet unit
    // tests. Applies to both EmergencyPacket and TerminationPacket, since
    // termination also needs to keep propagating through the mesh so
    // other relay nodes learn to stop forwarding and clear their cache
    // for this emergency_id.
    _relayPacket(packet);

    if (!_currentPolicy.allowUpload) {
      developer.log('Upload skipped — power saver mode active', name: 'MeshService');
      return;
    }
    _tryUpload(packet);
  }

  /// Forwards an already-validated, already-verified incoming packet to
  /// the next hop, if TTL allows. Does NOT re-enqueue to the local
  /// upload queue or re-run _tryUpload — that already happened once for
  /// this hop's own copy in _handlePayload. This only puts a
  /// TTL-decremented, hop-incremented copy back out over the mesh.
  ///
  /// NOTE: battery-aware relay-skip (documented in Mesh_Protocol.md —
  /// "devices below a battery threshold back off from relaying other
  /// people's traffic") is not yet wired in here; this device currently
  /// always relays regardless of its own battery level. Flagged as a
  /// known follow-up, not silently assumed done.
  void _relayPacket(MeshPacket packet) {
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
  }

  void _tryUpload(MeshPacket packet) {
    unawaited(() async {
      final online = await _backend.hasRealInternet();
      if (!online) return;
      final ok = await _backend.uploadPacket(packet);
      if (ok) {
        await _queue.markUploaded(packet.packetId);
        MeshMetrics.instance.uploaded++;
      }
    }());
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
      }
    }
  }

  @override
  void dispose() {
    _subscription.cancel();
    _policySub.cancel();
    _retryTimer.cancel();
    PowerModeController.instance.dispose();
  }
}
