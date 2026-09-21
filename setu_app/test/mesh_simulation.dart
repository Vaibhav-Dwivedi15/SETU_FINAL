import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:setu_app/features/relay/data/repositories/relay_log_repository.dart';
import 'package:setu_app/mesh/models/mesh_packet.dart';
import 'package:setu_app/mesh/services/local_queue_service.dart';
import 'package:setu_app/mesh/services/mesh_service.dart';
import 'package:setu_app/mesh/services/nearby_service.dart';
import 'package:setu_app/mesh/services/signing_service.dart';
import 'package:setu_app/services/backend_service.dart';

/// Multi-device mesh simulation harness (PRIORITY 5).
///
/// Builds N in-process SETU devices wired into a topology and runs real
/// [MeshServiceImpl] instances over fake transport/backend/queue, using
/// the EXISTING interfaces — NearbyService, BackendService,
/// LocalQueueService — rather than a parallel implementation.
///
/// WHAT THIS DOES AND DOES NOT PROVE — read before quoting any result.
///
/// Proven here (real code under test):
///   * MeshServiceImpl's receive path: decode, validate, signature gate,
///     termination handling, queue admission, relay dispatch.
///   * PriorityRelayQueue ordering and starvation behaviour under load.
///   * AdaptiveTtl's effect on how far a packet actually travels.
///   * Store-and-forward: packets held while offline, uploaded when
///     connectivity returns.
///
/// NOT proven here, and must never be presented as if it were:
///   * Anything about real radios. There is no Bluetooth, no Wi-Fi
///     Direct, no Nearby Connections. Hop delivery is a function call,
///     so timings from this harness are NOT mesh latency measurements.
///   * The native Kotlin engine (PacketRelayEngine,
///     NearbyConnectionsManager, MeshForegroundService). Its seen-cache
///     is MODELLED here by [_SeenCache] so multi-hop topologies behave
///     realistically, but the Kotlin itself is not executed — it needs
///     an instrumented Android test.
///   * Duplicate-storm suppression, which lives entirely in the native
///     service's jitter window.
///
/// Physical multi-device timing belongs in docs/MESH_PERFORMANCE.md,
/// measured on real handsets.
class SimulatedMesh {
  SimulatedMesh._(this.devices);

  final List<SimulatedDevice> devices;

  /// Devices in a line: 0 <-> 1 <-> 2 ... Every extra device adds a hop,
  /// which is how TTL exhaustion and multi-hop delivery get exercised.
  static Future<SimulatedMesh> chain(int count, {SigningBehaviour? signing}) async {
    final mesh = await _build(count, signing: signing);
    for (var i = 0; i < count - 1; i++) {
      mesh.link(i, i + 1);
    }
    return mesh;
  }

  /// Everyone in range of everyone — the dense-cluster case.
  static Future<SimulatedMesh> fullyConnected(int count, {SigningBehaviour? signing}) async {
    final mesh = await _build(count, signing: signing);
    for (var i = 0; i < count; i++) {
      for (var j = i + 1; j < count; j++) {
        mesh.link(i, j);
      }
    }
    return mesh;
  }

  /// Two clusters joined by a single device — the sparse case, and the
  /// one where losing the bridge device matters.
  static Future<SimulatedMesh> bridged(int leftSize, int rightSize,
      {SigningBehaviour? signing}) async {
    final total = leftSize + rightSize + 1;
    final mesh = await _build(total, signing: signing);
    final bridge = leftSize;
    for (var i = 0; i < leftSize; i++) {
      mesh.link(i, bridge);
      for (var j = i + 1; j < leftSize; j++) {
        mesh.link(i, j);
      }
    }
    for (var i = bridge + 1; i < total; i++) {
      mesh.link(bridge, i);
      for (var j = i + 1; j < total; j++) {
        mesh.link(i, j);
      }
    }
    return mesh;
  }

  static Future<SimulatedMesh> _build(int count, {SigningBehaviour? signing}) async {
    // Simulation must never touch platform storage.
    RelayLogRepository.disabled = true;

    final devices = <SimulatedDevice>[];
    for (var i = 0; i < count; i++) {
      devices.add(SimulatedDevice._(i, signing ?? SigningBehaviour.alwaysValid));
    }
    final mesh = SimulatedMesh._(devices);
    for (final device in devices) {
      device._mesh = mesh;
      device._start();
    }
    return mesh;
  }

  final Map<int, Set<int>> _links = {};

  void link(int a, int b) {
    _links.putIfAbsent(a, () => <int>{}).add(b);
    _links.putIfAbsent(b, () => <int>{}).add(a);
    devices[a]._nearby._announcePeer('device-$b');
    devices[b]._nearby._announcePeer('device-$a');
  }

  /// Simulates a device dropping out mid-relay: its links are cut, but
  /// the rest of the mesh must keep moving packets.
  void disconnect(int index) {
    final peers = _links[index] ?? <int>{};
    for (final peer in peers) {
      _links[peer]?.remove(index);
      devices[peer]._nearby._announcePeerLost('device-$index');
      devices[index]._nearby._announcePeerLost('device-$peer');
    }
    _links[index] = <int>{};
    devices[index].online = false;
  }

  Set<int> neighboursOf(int index) => _links[index] ?? <int>{};

  /// Called by a device's fake transport when it puts bytes on the air.
  void broadcastFrom(int senderIndex, Uint8List bytes) {
    for (final neighbour in neighboursOf(senderIndex)) {
      final target = devices[neighbour];
      if (!target.online) continue;
      // Models the NATIVE seen-cache: a device ignores a packet id it has
      // already handled. Without this, a fully-connected topology loops
      // forever — which is exactly what the native engine prevents on a
      // real device.
      if (!target._seen.admit(bytes)) continue;
      target._nearby._deliver(bytes);
    }
  }

  Future<void> settle({int rounds = 40}) async {
    for (var i = 0; i < rounds; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  void disposeAll() {
    for (final device in devices) {
      device.mesh_.dispose();
    }
    RelayLogRepository.disabled = false;
  }
}

enum SigningBehaviour { alwaysValid, alwaysInvalid }

class SimulatedDevice {
  SimulatedDevice._(this.index, this.signingBehaviour);

  final int index;
  final SigningBehaviour signingBehaviour;

  late final SimulatedMesh _mesh;
  late final _FakeNearbyService _nearby;
  late final _FakeBackendService backend;
  late final _FakeLocalQueue queue;
  late final MeshServiceImpl mesh_;

  final _SeenCache _seen = _SeenCache();

  /// Packets this device accepted (post-validation, post-signature).
  final List<MeshPacket> received = [];

  /// Bytes this device put on the air, in order.
  final List<Uint8List> transmitted = [];

  bool online = true;

  void _start() {
    _nearby = _FakeNearbyService(this);
    backend = _FakeBackendService();
    queue = _FakeLocalQueue();
    mesh_ = MeshServiceImpl(
      nearbyService: _nearby,
      signingService: signingBehaviour == SigningBehaviour.alwaysValid
          ? _AlwaysValidSigning()
          : _AlwaysInvalidSigning(),
      backendService: backend,
      queueService: queue,
    );
    mesh_.incomingPackets.listen(received.add);
  }

  /// Convenience: TTL each received copy of a packet arrived with.
  List<int> ttlsFor(String emergencyId) => received
      .map((packet) => packet.toJson())
      .where((json) => json['emergency_id'] == emergencyId)
      .map((json) => json['ttl'] as int)
      .toList();

  bool get relayedAnything => transmitted.isNotEmpty;
}

/// Per-device model of the native PacketRelayEngine seen-cache.
class _SeenCache {
  final Set<String> _ids = {};

  bool admit(Uint8List bytes) {
    try {
      final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      final id = json['packet_id'] as String?;
      if (id == null) return false;
      // Relayed copies keep the same packet_id, which is precisely how
      // the real engine stops loops.
      return _ids.add(id);
    } catch (_) {
      return false;
    }
  }
}

class _FakeNearbyService implements NearbyService {
  _FakeNearbyService(this._device);

  final SimulatedDevice _device;
  final StreamController<NearbyEvent> _controller = StreamController<NearbyEvent>.broadcast();

  Duration? lastScanInterval;
  bool lastAllowRelay = true;

  /// Set true to simulate a transport that throws — a radio failure must
  /// not stop the relay pump.
  bool failSends = false;

  @override
  Stream<NearbyEvent> get events => _controller.stream;

  @override
  Future<void> originate(Uint8List bytes, String packetId) async {
    if (failSends) throw StateError('simulated transport failure');
    _device.transmitted.add(bytes);
    _device._seen.admit(bytes); // never relay our own transmission back
    _device._mesh.broadcastFrom(_device.index, bytes);
  }

  @override
  Future<void> updatePolicy({
    required Duration scanInterval,
    required Duration discoveryInterval,
    required bool allowRelay,
  }) async {
    lastScanInterval = scanInterval;
    lastAllowRelay = allowRelay;
  }

  @override
  Future<Map<dynamic, dynamic>?> fetchRelayStats() async => null;

  void _deliver(Uint8List bytes) {
    if (_controller.isClosed) return;
    _controller.add(PayloadReceived('peer', bytes));
  }

  void _announcePeer(String endpointId) {
    if (_controller.isClosed) return;
    _controller.add(PeerConnected(endpointId));
  }

  void _announcePeerLost(String endpointId) {
    if (_controller.isClosed) return;
    _controller.add(PeerDisconnected(endpointId));
  }
}

class _FakeBackendService extends BackendService {
  /// Flip mid-test to simulate the internet appearing or disappearing.
  bool internetAvailable = false;

  /// Flip to simulate the backend being reachable but broken (5xx).
  bool backendHealthy = true;

  final List<String> uploadedPacketIds = [];

  @override
  Future<bool> hasRealInternet() async => internetAvailable;

  @override
  Future<bool> uploadPacket(MeshPacket packet) async {
    if (!internetAvailable || !backendHealthy) return false;
    uploadedPacketIds.add(packet.packetId);
    return true;
  }

  @override
  Future<List<String>?> fetchResponderKeys() async => null;
}

/// In-memory stand-in for the sqflite-backed durable queue. Same
/// contract, no platform channel.
class _FakeLocalQueue extends LocalQueueService {
  final Map<String, MeshPacket> _packets = {};
  final Set<String> _uploaded = {};

  @override
  Future<void> init() async {}

  @override
  Future<void> enqueue(MeshPacket packet) async {
    _packets.putIfAbsent(packet.packetId, () => packet);
  }

  @override
  Future<void> markUploaded(String packetId) async => _uploaded.add(packetId);

  @override
  Future<List<MeshPacket>> getPendingPackets() async => _packets.entries
      .where((entry) => !_uploaded.contains(entry.key))
      .map((entry) => entry.value)
      .toList();

  @override
  Future<void> pruneUploaded({Duration maxAge = const Duration(days: 3)}) async {}

  @override
  Future<void> markEmergencyClosed(String emergencyId, {String? keepPacketId}) async {
    _packets.removeWhere((packetId, packet) {
      if (keepPacketId != null && packetId == keepPacketId) return false;
      final json = packet.toJson();
      return json['emergency_id'] == emergencyId;
    });
  }

  int get storedCount => _packets.length;
  int get pendingCount => _packets.length - _uploaded.length;
}

class _AlwaysValidSigning extends SigningService {
  @override
  Future<bool> verify(String payload, String senderPublicKeyHex, String signatureHex) async => true;
}

class _AlwaysInvalidSigning extends SigningService {
  @override
  Future<bool> verify(String payload, String senderPublicKeyHex, String signatureHex) async => false;
}
