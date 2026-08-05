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

  /// Added Aug 4 2026: real delivery confirmations for packets THIS
  /// device originated -- fires when an AckPacket arrives whose
  /// emergencyId matches something this device sent. Replaces the
  /// optimistic "Delivered" status sos_repository.dart currently shows
  /// immediately on send with an actual confirmed-reached-the-backend
  /// signal. See ack_packet.dart for the full flow.
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
    // Responder registry sync: closes the termination-authorization gap
    // documented in responder_registry.dart. Every 5 minutes (and once at
    // startup), pull the trusted-responder public key list from the
    // backend so ResponderRegistry stops fail-open-accepting terminations
    // from any valid keypair. 5 minutes, not more frequent — this list
    // changes rarely (responder onboarding/offboarding), and each sync is
    // a network call gated on real internet, same as upload retries.
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
  final PacketValidator _validator = PacketValidator(); // Security Lead's module
  final _incomingController = StreamController<MeshPacket>.broadcast();
  final Set<String> _closedEmergencyIds = {};

  // Added Aug 4 2026 -- see AckPacket docstring for the full flow.
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

  /// MARK II battery-tiered duty cycling: pushes the current policy's
  /// scan/discovery intervals + relay flag down to the native Foreground
  /// Service so power-saver mode actually reduces radio-on time, not
  /// just gates relay/upload here in Dart. Fire-and-forget: if this
  /// fails (e.g. native side not bound yet), native keeps whatever duty
  /// cycle it already had -- never blocks mesh startup on this.
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
    // Not run through PacketValidator: replay/timestamp protection exists
    // to catch packets ARRIVING from the mesh, not ones this device just
    // created itself (a fresh packet's own nonce/timestamp always passes
    // trivially — validating it here would be redundant, not incorrect).
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
      MeshMetrics.instance.notify();
      return;
    }
    developer.log('Packet passed PacketValidator: ${packet.packetId}', name: 'MeshService');

    final isValid = await _signing.verify(packet.signaturePayload, packet.senderId, packet.signature);
    if (!isValid) {
      developer.log('Dropped packet with invalid signature: ${packet.packetId}', name: 'MeshService');
      MeshMetrics.instance.dropped++;
      MeshMetrics.instance.notify();
      return;
    }
    developer.log('Packet signature VERIFIED: ${packet.packetId}', name: 'MeshService');

    if (packet is TerminationPacket) {
      final (authorized, enforced) = ResponderRegistry.instance.checkResponder(packet.senderId);
      if (!authorized) {
        developer.log('Dropped termination from unauthorized responder: ${packet.senderId}', name: 'MeshService');
        MeshMetrics.instance.dropped++;
        MeshMetrics.instance.notify();
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
      return;
    }

    MeshMetrics.instance.received++;
    MeshMetrics.instance.notify();
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

    // Added Aug 4 2026: AckPacket and AlertPacket are mesh-only —
    // backend's /ingest schema only understands emergency/termination
    // packets today, so uploading these would just be rejected. They
    // still relay (above) so they keep propagating through the mesh
    // toward whoever they're meant for, they just never hit _tryUpload.
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

  /// Forwards an already-validated, already-verified incoming packet to
  /// the next hop, if TTL allows. Does NOT re-enqueue to the local
  /// upload queue or re-run _tryUpload — that already happened once for
  /// this hop's own copy in _handlePayload. This only puts a
  /// TTL-decremented, hop-incremented copy back out over the mesh.
  ///
  /// Battery-aware relay guard: gated on MeshPolicy.allowRelay, which
  /// BatteryService already drives to false below 20% battery (see
  /// mesh_policy.dart / battery_service.dart — PowerMode.powerSaver).
  /// This only gates RELAYING OTHER DEVICES' traffic. A device's own SOS
  /// always goes out regardless of battery — originate() never checks
  /// _currentPolicy at all, by design.
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
  }

  void _tryUpload(MeshPacket packet) {
    // Ack/Alert packets are mesh-only -- see the comment in
    // _handlePayload's AckPacket/AlertPacket branch for why. Guarding
    // here too covers the self-originate path (originate() always
    // calls _tryUpload at the end), not just incoming relayed packets.
    if (packet is AckPacket || packet is AlertPacket) return;

    unawaited(() async {
      final online = await _backend.hasRealInternet();
      if (!online) return;
      final ok = await _backend.uploadPacket(packet);
      if (ok) {
        await _queue.markUploaded(packet.packetId);
        MeshMetrics.instance.uploaded++;
        MeshMetrics.instance.notify();
        if (packet is EmergencyPacket) {
          unawaited(_originateAck(packet));
        }
      }
    }());
  }

  /// Added Aug 4 2026: fires the moment THIS device (acting as the
  /// exit node, "Pn") successfully hands a packet to the backend --
  /// whether that's this device's own SOS (internet was available the
  /// whole time) or a packet relayed in from someone else's mesh. The
  /// ack travels back through the mesh the same way any packet does;
  /// only the device whose _originatedEmergencyIds contains this
  /// emergencyId will actually surface it (see the AckPacket branch in
  /// _handlePayload above) -- everyone else just relays it onward.
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

  /// Pulls the current trusted-responder public key list from the backend
  /// and pushes it into ResponderRegistry. Skips silently (retries next
  /// cycle) if offline or the fetch fails — never clears an existing,
  /// previously-synced registry just because one sync attempt failed.
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
