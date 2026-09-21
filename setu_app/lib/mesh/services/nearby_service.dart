import 'package:flutter/services.dart';
import 'package:setu_app/security/security_constants.dart';

sealed class NearbyEvent {
  const NearbyEvent();
}

class PeerConnected extends NearbyEvent {
  const PeerConnected(this.endpointId);
  final String endpointId;
}

class PeerDisconnected extends NearbyEvent {
  const PeerDisconnected(this.endpointId);
  final String endpointId;
}

class PayloadReceived extends NearbyEvent {
  const PayloadReceived(this.endpointId, this.bytes);
  final String endpointId;
  final Uint8List bytes;
}

abstract class NearbyService {
  /// Sends a self-originated packet. Advertising/discovery/relay are all
  /// handled natively by the Foreground Service now — Dart doesn't control
  /// them directly anymore.
  Future<void> originate(Uint8List bytes, String packetId);
  Stream<NearbyEvent> get events;

  /// Added for MARK II battery-tiered duty cycling. Nearby Connections
  /// (the underlying Android API) does NOT expose a "BLE-only vs Wi-Fi
  /// Direct" switch — Strategy controls connection topology, not radio
  /// choice, and the library picks the radio internally. The real,
  /// honest battery lever is duty-cycling: how often the native layer
  /// bursts advertising/discovery on, then sleeps. This pushes
  /// MeshPolicy's existing scanInterval/discoveryInterval down to the
  /// native Foreground Service so power-saver mode actually reduces
  /// radio-on time instead of just gating relay/upload in Dart.
  Future<void> updatePolicy({
    required Duration scanInterval,
    required Duration discoveryInterval,
    required bool allowRelay,
  });

  /// PRIORITY 1 -- reads the native engine's counters (duplicates
  /// filtered, relays suppressed by storm protection, discovery and
  /// connection-establishment timings). Those stages live entirely in
  /// Kotlin -- Dart only ever sees the resulting PeerConnected event --
  /// so without this they cannot be measured at all.
  ///
  /// Concrete default rather than an abstract method ON PURPOSE: existing
  /// implementations (and test fakes) keep compiling untouched, and an
  /// older native build that has no `getRelayStats` leaves those metrics
  /// reading "not measured" instead of a fabricated zero.
  Future<Map<dynamic, dynamic>?> fetchRelayStats() async => null;
}

class PlatformNearbyService implements NearbyService {
  static const _methodChannel = MethodChannel('com.setu.mesh/methods');
  static const _eventChannel = EventChannel('com.setu.mesh/events');

  @override
  Future<void> originate(Uint8List bytes, String packetId) =>
      _methodChannel.invokeMethod('originate', {'bytes': bytes, 'packetId': packetId});

  @override
  Future<void> updatePolicy({
    required Duration scanInterval,
    required Duration discoveryInterval,
    required bool allowRelay,
  }) =>
      _methodChannel.invokeMethod('updateMeshPolicy', {
        'scanIntervalMs': scanInterval.inMilliseconds,
        'discoveryIntervalMs': discoveryInterval.inMilliseconds,
        'allowRelay': allowRelay,
        // Sep 21 2026 (Vib, Bulk Sprint 3): SecurityConstants.maxTTL is
        // declared separately in Kotlin (PacketRelayEngine.MAX_TTL) with
        // no compile-time or runtime mechanism enforcing the two stay
        // equal -- see docs/mesh/TTL.md and
        // docs/security/NATIVE_SIGNATURE_VERIFICATION_DESIGN.md's sibling
        // doc for the fuller discussion. Rather than build shared-constant
        // infra (out of scope -- "do not rewrite architecture" per this
        // sprint's rules), this piggybacks on the policy channel that
        // already exists: native compares this against its own MAX_TTL
        // and logs a loud warning on mismatch, so a future accidental
        // drift is at least VISIBLE in logs instead of silent. Does not
        // change TTL behavior in any way -- purely a diagnostic value.
        'maxTtl': SecurityConstants.maxTTL,
      });

  @override
  Future<Map<dynamic, dynamic>?> fetchRelayStats() async {
    try {
      final stats = await _methodChannel.invokeMethod('getRelayStats');
      return stats is Map ? stats : null;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  @override
  Stream<NearbyEvent> get events {
    return _eventChannel.receiveBroadcastStream().map((event) {
      final map = Map<String, dynamic>.from(event as Map);
      switch (map['type'] as String) {
        case 'peer_connected':
          return PeerConnected(map['endpointId'] as String);
        case 'peer_disconnected':
          return PeerDisconnected(map['endpointId'] as String);
        case 'payload_received':
          return PayloadReceived(map['endpointId'] as String, map['bytes'] as Uint8List);
        default:
          throw StateError('Unknown NearbyEvent type: ${map['type']}');
      }
    });
  }
}
