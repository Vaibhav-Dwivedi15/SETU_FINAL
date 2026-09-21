import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:typed_data';

import '../../security/packet_validator.dart';
import '../../security/security_constants.dart';
import '../../security/security_exceptions.dart';
import '../../services/backend_service.dart';
import '../../services/battery_service.dart';
import '../../services/power_mode.dart';
import '../../services/power_mode_controller.dart';
import '../../features/sos/data/services/ack_packet_builder.dart';
import '../../features/relay/data/models/relay_log_entry.dart';
import '../../features/relay/data/repositories/relay_log_repository.dart';
import '../enums/emergency_priority.dart';
import '../models/ack_packet.dart';
import '../models/alert_packet.dart';
import '../models/emergency_packet.dart';
import '../models/mesh_packet.dart';
import '../models/packet_factory.dart';
import '../models/termination_packet.dart';
import 'adaptive_ttl.dart';
import 'local_queue_service.dart';
import 'mesh_metrics.dart';
import 'mesh_policy.dart';
import 'nearby_service.dart';
import 'priority_relay_queue.dart';
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
    PriorityRelayQueue? relayQueue,
  })  : _nearby = nearbyService,
        _signing = signingService,
        _backend = backendService,
        _queue = queueService,
        _relayQueue = relayQueue ?? PriorityRelayQueue() {
    _subscription = _nearby.events.listen(_handleNearbyEvent);
    _retryTimer = Timer.periodic(const Duration(seconds: 30), (_) => _retryPendingUploads());
    // Sep 21 2026 (Vib): also prunes already-uploaded rows older than 3
    // days on the same cadence as the registry sync -- LocalQueueService
    // .pruneUploaded() existed but was never called from anywhere, so the
    // durable queue's uploaded rows only ever grew. Cheap (DELETE with an
    // indexed-by-nature boolean + timestamp filter) and safe to run every
    // 5 minutes; never touches rows still pending upload.
    _registryTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      _syncResponderRegistry();
      unawaited(_queue.pruneUploaded());
    });
    // Sep 2026 (PRIORITY 1): pulls duplicate/suppression counters and
    // discovery/connection timings up from the native engine. Read-only,
    // once a minute -- it must not become a source of load itself.
    _statsTimer = Timer.periodic(const Duration(minutes: 1), (_) => _pullNativeStats());
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

  /// PRIORITY 2 -- in-memory, priority-ordered relay queue. Distinct from
  /// [_queue] (LocalQueueService), which is the durable store-and-forward
  /// queue for backend upload and is unchanged.
  final PriorityRelayQueue _relayQueue;

  final PacketValidator _validator = PacketValidator();
  final _incomingController = StreamController<MeshPacket>.broadcast();
  final Set<String> _closedEmergencyIds = {};

  final AckPacketBuilder _ackBuilder = AckPacketBuilder();
  final Set<String> _originatedEmergencyIds = {};

  /// Sep 21 2026 (Vib, mesh-hardening pass): guards against the SAME
  /// packetId being uploaded twice concurrently. _tryUpload() fires on
  /// every freshly received/originated packet, and _retryPendingUploads()
  /// independently re-reads getPendingPackets() every 30s -- without this
  /// guard, nothing stops both from calling _backend.uploadPacket() for
  /// the same packet if the 30s timer fires while an in-flight upload for
  /// that same packet hasn't yet reached markUploaded(). Client-side only:
  /// this does not depend on (or replace) backend-side idempotency, it
  /// just stops the Dart layer from *causing* the race in the first place.
  final Set<String> _uploadingPacketIds = {};

  final _acknowledgmentsController = StreamController<AckPacket>.broadcast();
  late final StreamSubscription<NearbyEvent> _subscription;
  late final StreamSubscription<PowerMode> _policySub;
  late final Timer _retryTimer;
  late final Timer _registryTimer;
  late final Timer _statsTimer;
  MeshPolicy _currentPolicy = MeshPolicy.fromPowerMode(PowerMode.full);

  /// Endpoints currently connected, tracked from the native peer events.
  /// Feeds cluster density into AdaptiveTtl -- in a dense cluster a
  /// low-priority packet does not need its full hop budget.
  final Set<String> _connectedPeers = {};

  bool _draining = false;
  bool _disposed = false;

  @override
  Stream<MeshPacket> get incomingPackets => _incomingController.stream;

  @override
  Stream<AckPacket> get acknowledgments => _acknowledgmentsController.stream;

  /// Exposed for the debug metrics screen and the test harness.
  int get connectedPeerCount => _connectedPeers.length;
  Map<String, int> get relayQueueDepth => _relayQueue.depthSnapshot();

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

  Future<void> _pullNativeStats() async {
    try {
      final stats = await _nearby.fetchRelayStats();
      if (stats != null) MeshMetrics.instance.applyNativeStats(stats);
    } catch (e) {
      // A native build without getRelayStats simply leaves those metrics
      // unmeasured -- never a reason to disturb the relay path.
      developer.log('Native relay stats unavailable: $e', name: 'MeshService');
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

    // Self-originated traffic bypasses the priority queue entirely: this
    // device's own SOS is never made to wait behind anything, including
    // other critical packets it happens to be relaying.
    final dispatch = Stopwatch()..start();
    await _nearby.originate(bytes, packet.packetId);
    dispatch.stop();
    MeshMetrics.instance.relayDispatch.addMicros(dispatch.elapsedMicroseconds);

    developer.log('Packet handed to NearbyService.originate: ${packet.packetId} (${bytes.length} bytes)', name: 'MeshService');
    MeshMetrics.instance.sent++;
    MeshMetrics.instance.recordBattery(BatteryService.instance.batteryLevel);
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
        _connectedPeers.add(event.endpointId);
        developer.log(
          'Peer connected: ${event.endpointId} (cluster size ${_connectedPeers.length})',
          name: 'MeshService',
        );
      case PeerDisconnected():
        _connectedPeers.remove(event.endpointId);
        // Existing behaviour preserved deliberately: a disconnected peer
        // is simply removed from the cluster. Nothing in the relay path
        // blocks on it -- queued packets keep draining to whoever is
        // still connected.
        developer.log(
          'Peer disconnected: ${event.endpointId} (cluster size ${_connectedPeers.length})',
          name: 'MeshService',
        );
      case PayloadReceived():
        developer.log('Raw payload received: ${event.bytes.length} bytes', name: 'MeshService');
        _handlePayload(event.bytes);
    }
  }

  Future<void> _handlePayload(Uint8List bytes) async {
    // PRIORITY 1: measures what THIS device adds to a multi-hop route --
    // decode + validate + verify + queue admission.
    final receiveStopwatch = Stopwatch()..start();

    // Sep 21 2026 (Vib, mesh-hardening pass): SecurityConstants
    // .maxPacketSize existed but was never actually enforced anywhere --
    // checked here, before touching jsonDecode, so an oversized payload
    // is rejected on raw byte length alone rather than being handed to
    // the JSON parser first. Cheapest possible place for this check, and
    // it can never reject a legitimate packet: real EmergencyPacket JSON
    // is well under 1KB even with a full emergency_contacts list.
    if (bytes.length > SecurityConstants.maxPacketSize) {
      developer.log(
        'Dropped oversized payload: ${bytes.length} bytes (max ${SecurityConstants.maxPacketSize})',
        name: 'MeshService',
      );
      MeshMetrics.instance.dropped++;
      MeshMetrics.instance.notify();
      unawaited(RelayLogRepository.instance.log(
        type: RelayLogType.dropped,
        packetId: 'unknown',
        detail: 'Oversized payload (${bytes.length} bytes)',
      ));
      return;
    }

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

    // Signature verification is the most expensive step in this path, so
    // it is timed separately -- if relay latency ever regresses, this
    // number says whether crypto is the cause.
    final isValid = await MeshMetrics.instance.signatureVerify.time(
      () => _signing.verify(packet.signaturePayload, packet.senderId, packet.signature),
    );
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
      // NOTE: the durable-queue sweep for this emergency_id does NOT
      // happen here. It used to, and that was the bug (see below) --
      // sweeping this early runs *before* the generic `_queue.enqueue`
      // further down (which fires for every packet type, including this
      // termination packet itself), so the sweep would find nothing to
      // remove yet, and the termination packet inserted afterward would
      // sit in the durable queue forever with nothing left to ever clear
      // it. The sweep is done instead right after that generic enqueue
      // (see below), by which point this termination packet's own row
      // exists and is swept along with everything else for the emergency
      // -- upload is unaffected, since _tryUpload() works off the
      // in-memory `packet` object, not a DB read. Found via real
      // `flutter test` execution on real hardware, Bulk Sprint 5 Phase 18
      // (docs/mesh/SPRINT5_INTEGRATION_VALIDATION.md §15) -- prior
      // sprints could only source-review this path, since no Dart SDK
      // was ever available in the sandbox they ran in.
      //
      // Sweep the in-memory relay queue here though -- unlike the durable
      // queue, this one is populated by _relayPacket() further down, so a
      // packet for this emergency can only be in it if it arrived on a
      // *previous* call to this method, never as a side effect of the
      // current one. No ordering hazard.
      final purged = _relayQueue.removeEmergency(packet.emergencyId);
      developer.log(
        'Emergency ${packet.emergencyId} marked CLOSED (purged $purged queued relay(s))',
        name: 'MeshService',
      );
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
    MeshMetrics.instance.recordBattery(BatteryService.instance.batteryLevel);
    MeshMetrics.instance.notify();
    unawaited(RelayLogRepository.instance.log(
      type: RelayLogType.received,
      packetId: packet.packetId,
      detail: '${packet.type.name} packet, hop ${packet.hopCount}',
    ));
    await _queue.enqueue(packet);
    if (packet is TerminationPacket) {
      // Now that this termination packet's own row exists, sweep the
      // durable queue for its emergency_id -- this removes every packet
      // for the closed incident, including the termination packet
      // itself. Upload is unaffected: _tryUpload() below still fires off
      // the in-memory `packet` object regardless of whether its DB row
      // survives.
      await _queue.markEmergencyClosed(packet.emergencyId);
    }
    _incomingController.add(packet);
    developer.log('Packet ACCEPTED and queued: ${packet.packetId} (total received=${MeshMetrics.instance.received})', name: 'MeshService');

    _relayPacket(packet);

    receiveStopwatch.stop();
    MeshMetrics.instance.receiveToRelay.addMicros(receiveStopwatch.elapsedMicroseconds);

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

  /// Admits a received packet to the priority relay queue.
  ///
  /// Was: build the next hop and hand it straight to the transport.
  /// Now: decide, enqueue by priority, and let [_drainRelayQueue] dispatch
  /// in priority order. TTL and battery guards are unchanged in meaning,
  /// only in where they sit -- TTL is now evaluated at dispatch time
  /// (using AdaptiveTtl), which is also when cluster density is known.
  void _relayPacket(MeshPacket packet) {
    final decision = PriorityRelayQueue.decide(
      packet: packet,
      allowRelay: _currentPolicy.allowRelay,
      allowUpload: _currentPolicy.allowUpload,
    );

    if (!decision.relay) {
      developer.log(
        'Relay skipped — ${decision.reason}: ${packet.packetId}',
        name: 'MeshService',
      );
      return;
    }

    // Cheap pre-check so a packet that cannot possibly be forwarded never
    // occupies a queue slot. AdaptiveTtl re-checks at dispatch.
    if (!AdaptiveTtl.canRelay(packet.ttl)) {
      developer.log('Not relaying further — TTL exhausted: ${packet.packetId}', name: 'MeshService');
      return;
    }

    final admitted = _relayQueue.enqueue(packet);
    if (!admitted) {
      developer.log(
        'Relay queue full — dropped ${PriorityRelayQueue.priorityOf(packet).name} packet ${packet.packetId}',
        name: 'MeshService',
      );
      MeshMetrics.instance.dropped++;
      MeshMetrics.instance.notify();
      unawaited(RelayLogRepository.instance.log(
        type: RelayLogType.dropped,
        packetId: packet.packetId,
        detail: 'Relay queue full (overflow shed by priority)',
      ));
      return;
    }

    unawaited(_drainRelayQueue());
  }

  /// Dispatches queued relays highest-priority-first.
  ///
  /// Re-entrancy: [_draining] makes this a single logical pump. Because
  /// each dispatch is awaited, packets that arrive mid-drain land in the
  /// queue and are re-ranked on the next iteration -- which is what lets
  /// a CRITICAL packet arriving during a burst preempt routine traffic
  /// that was already queued ahead of it.
  Future<void> _drainRelayQueue() async {
    if (_draining || _disposed) return;
    _draining = true;
    try {
      while (!_disposed) {
        final entry = _relayQueue.dequeue();
        if (entry == null) break;

        MeshMetrics.instance.recordQueueWait(entry.priority.name, entry.waited);

        // Re-check the battery policy at dispatch time, not just at
        // admission: a long drain under load can outlive the power mode
        // that started it.
        if (!_currentPolicy.allowRelay) {
          developer.log(
            'Relay halted mid-drain — power saver engaged: ${entry.packet.packetId}',
            name: 'MeshService',
          );
          break;
        }

        await _dispatchRelay(entry.packet, entry.priority);
      }
    } finally {
      _draining = false;
    }
  }

  Future<void> _dispatchRelay(MeshPacket packet, EmergencyPriority priority) async {
    final age = DateTime.now().toUtc().difference(packet.timestamp.toUtc());

    final nextTtl = AdaptiveTtl.nextTtl(
      currentTtl: packet.ttl,
      packetAge: age,
      priority: priority,
      hopCount: packet.hopCount,
      connectedPeerCount: _connectedPeers.isEmpty ? null : _connectedPeers.length,
    );

    if (!AdaptiveTtl.canRelay(nextTtl)) {
      developer.log(
        'Not relaying further — ${AdaptiveTtl.explain(
          currentTtl: packet.ttl,
          nextTtl: nextTtl,
          priority: priority,
          packetAge: age,
          connectedPeerCount: _connectedPeers.length,
        )}: ${packet.packetId}',
        name: 'MeshService',
      );
      return;
    }

    final MeshPacket relayed;
    try {
      relayed = packet.withRelayHop(ttlOverride: nextTtl);
    } catch (e) {
      developer.log('Failed to build relay hop for ${packet.packetId}: $e', name: 'MeshService');
      MeshMetrics.instance.relayFailures++;
      MeshMetrics.instance.notify();
      return;
    }

    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(relayed.toJson())));
    MeshMetrics.instance.relayAttempts++;

    final dispatch = Stopwatch()..start();
    try {
      await _nearby.originate(bytes, relayed.packetId);
    } catch (e) {
      // A transport failure must not stop the pump -- the next packet in
      // the queue still gets its turn. This is the "failed node must not
      // block the pipeline" rule, enforced at the queue level.
      MeshMetrics.instance.relayFailures++;
      MeshMetrics.instance.notify();
      developer.log('Relay dispatch failed for ${relayed.packetId}: $e', name: 'MeshService');
      return;
    } finally {
      dispatch.stop();
      MeshMetrics.instance.relayDispatch.addMicros(dispatch.elapsedMicroseconds);
    }

    developer.log(
      'Relayed packet to next hop: ${relayed.packetId} '
      '${AdaptiveTtl.explain(
        currentTtl: packet.ttl,
        nextTtl: nextTtl,
        priority: priority,
        packetAge: age,
        connectedPeerCount: _connectedPeers.length,
      )} hop=${relayed.hopCount} priority=${priority.name}',
      name: 'MeshService',
    );
    MeshMetrics.instance.relayed++;
    MeshMetrics.instance.notify();
    unawaited(RelayLogRepository.instance.log(
      type: RelayLogType.relayed,
      packetId: relayed.packetId,
      detail: 'Carried forward as ${priority.name}, now hop ${relayed.hopCount}',
    ));
  }

  void _tryUpload(MeshPacket packet) {
    if (packet is AckPacket || packet is AlertPacket) return;

    // In-flight guard: if _retryPendingUploads() (or another concurrent
    // call to _tryUpload for the same packet -- e.g. relayed twice before
    // dedup) is already uploading this packetId, skip. Released in the
    // `finally` below regardless of outcome, so a failed upload doesn't
    // permanently block a later retry.
    if (!_uploadingPacketIds.add(packet.packetId)) {
      developer.log('Upload already in flight for ${packet.packetId} — skipping', name: 'MeshService');
      return;
    }

    unawaited(() async {
      try {
        final online = await _backend.hasRealInternet();
        if (!online) return;

        final upload = Stopwatch()..start();
        final ok = await _backend.uploadPacket(packet);
        upload.stop();
        MeshMetrics.instance.backendUpload.addMicros(upload.elapsedMicroseconds);

        if (ok) {
          await _markPacketDelivered(packet, detail: 'Delivered to backend');
        }
      } finally {
        _uploadingPacketIds.remove(packet.packetId);
      }
    }());
  }

  /// Shared "this packet reached the backend" bookkeeping -- used by both
  /// _tryUpload (first-attempt path) and _retryPendingUploads (30s retry
  /// path). Previously only _tryUpload did this, which meant a packet
  /// delivered exclusively via the retry loop (e.g. no internet on first
  /// receive) never originated an ack, leaving the sender's local status
  /// stuck at "Sent" forever even though the backend had it. Recovery and
  /// SOS both go through this same path, so both get the fix.
  Future<void> _markPacketDelivered(MeshPacket packet, {required String detail}) async {
    await _queue.markUploaded(packet.packetId);
    MeshMetrics.instance.uploaded++;
    _recordEndToEnd(packet);
    MeshMetrics.instance.notify();
    unawaited(RelayLogRepository.instance.log(
      type: RelayLogType.uploaded,
      packetId: packet.packetId,
      detail: detail,
    ));
    if (packet is EmergencyPacket) {
      unawaited(_originateAck(packet));
    }
  }

  /// Origin timestamp -> backend delivery. This is the only end-to-end
  /// figure SETU can measure without extra traffic, because every packet
  /// already carries the originating device's timestamp on the wire.
  ///
  /// Clock-skew caveat (documented in MeshMetrics): a sample is only as
  /// good as the two devices' clock agreement. PacketValidator already
  /// rejects anything beyond allowedClockSkew, and LatencySamples
  /// discards negatives, so a badly-set clock degrades the sample count
  /// rather than corrupting the average.
  void _recordEndToEnd(MeshPacket packet) {
    final delivered = DateTime.now().toUtc();
    MeshMetrics.instance.endToEnd.add(delivered.difference(packet.timestamp.toUtc()));
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
      // Same in-flight guard as _tryUpload -- if an immediate upload for
      // this exact packet is already running (e.g. it was just received
      // moments before this 30s tick fired), skip it here rather than
      // uploading it a second time concurrently.
      if (!_uploadingPacketIds.add(packet.packetId)) {
        developer.log('Retry skipped, upload already in flight: ${packet.packetId}', name: 'MeshService');
        continue;
      }
      try {
        final upload = Stopwatch()..start();
        final ok = await _backend.uploadPacket(packet);
        upload.stop();
        MeshMetrics.instance.backendUpload.addMicros(upload.elapsedMicroseconds);
        if (ok) {
          // Sep 21 2026 (Vib): previously this path did NOT call
          // _originateAck -- a packet delivered only via retry (e.g. no
          // internet on first receive/originate) never acked the sender,
          // so History/Recovery status stayed at "Sent" forever even
          // though the backend had it. Now shares _markPacketDelivered
          // with _tryUpload so both paths behave identically.
          await _markPacketDelivered(packet, detail: 'Delivered to backend (retry)');
        }
      } finally {
        _uploadingPacketIds.remove(packet.packetId);
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _relayQueue.clear();
    _subscription.cancel();
    _policySub.cancel();
    _retryTimer.cancel();
    _registryTimer.cancel();
    _statsTimer.cancel();
    _acknowledgmentsController.close();
    // Sep 21 2026 (Vib): was previously never closed here, unlike
    // _acknowledgmentsController -- a StreamController with no listeners
    // left open isn't a functional bug, but it's an asymmetry with no
    // reason behind it and a real (if minor) resource-cleanliness gap.
    _incomingController.close();
    PowerModeController.instance.dispose();
  }
}
