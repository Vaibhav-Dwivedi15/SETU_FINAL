import 'package:flutter/services.dart';

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
      });

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
