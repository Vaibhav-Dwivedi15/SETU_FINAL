import 'dart:async';
import 'dart:developer' as developer;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/services.dart';

/// Whether THIS device currently has its own internet connectivity.
/// Not about mesh state -- purely "can I reach the internet directly."
enum NetworkStatus { online, offline }

/// Starts/stops the native mesh foreground service based on real
/// connectivity changes, instead of the mesh service running
/// unconditionally for the whole lifetime of the app process.
///
/// WHY THIS EXISTS (Aug 4 2026 gap analysis): MeshForegroundService
/// currently starts once, in MeshChannelHandler.start(), which runs
/// from MainActivity on every app launch -- it has no notion of
/// "online" vs "offline" and never stops itself. That's not wrong for
/// a hackathon demo (a phone with signal can still usefully relay for
/// a neighbour without signal), but it does mean the phone's own
/// connectivity state was never actually being used as a signal for
/// anything, which was the specific behaviour asked for: react to
/// this device going offline, not just "always be on".
///
/// Aug 5 2026: this was found NOT actually wired up anywhere --
/// enableAutoMode() was never called from main.dart, and even when
/// called, both branches of _applyConnectivity did the exact same
/// thing (mesh always ensured running either way), so the app never
/// actually surfaced "online" vs "offline" to anything. Fixed to
/// track real NetworkStatus and expose it as a stream so the home
/// screen / SOS flow can show the user their actual connectivity
/// state, and so triggerSOS() can react differently for the online
/// vs offline case per the product vision.
class ConnectivityMeshController {
  ConnectivityMeshController._();

  static final ConnectivityMeshController instance = ConnectivityMeshController._();

  static const MethodChannel _channel = MethodChannel('com.setu.mesh/methods');

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  bool _meshCurrentlyRunning = true; // MeshChannelHandler.start() already ran it at launch.

  final _statusController = StreamController<NetworkStatus>.broadcast();
  NetworkStatus _currentStatus = NetworkStatus.online; // optimistic default until first real check

  /// Live connectivity state. Home screen / SOS flow subscribe to this
  /// to show "Online" / "Offline -- Mesh active" without polling.
  Stream<NetworkStatus> get statusStream => _statusController.stream;

  NetworkStatus get currentStatus => _currentStatus;

  Future<void> enableAutoMode() async {
    if (_subscription != null) return; // idempotent

    final initial = await _connectivity.checkConnectivity();
    await _applyConnectivity(initial);

    _subscription = _connectivity.onConnectivityChanged.listen(_applyConnectivity);
  }

  Future<void> disableAutoMode() async {
    await _subscription?.cancel();
    _subscription = null;
    await _ensureMeshRunning(); // always-on is the safe default to fall back to
  }

  Future<void> _applyConnectivity(List<ConnectivityResult> results) async {
    final isOffline = results.isEmpty || results.every((r) => r == ConnectivityResult.none);
    final newStatus = isOffline ? NetworkStatus.offline : NetworkStatus.online;

    if (newStatus != _currentStatus) {
      _currentStatus = newStatus;
      _statusController.add(newStatus);
      developer.log('Network status changed -> ${newStatus.name}', name: 'ConnectivityMeshController');
    }

    // Mesh stays on regardless of online/offline -- a phone with signal
    // is still a useful relay for a neighbour without any. This
    // guarantees the radios/foreground service are alive; the
    // online/offline distinction above is purely informational for the
    // UI and for triggerSOS()'s branching, not a mesh on/off switch.
    await _ensureMeshRunning();
  }

  Future<void> _ensureMeshRunning() async {
    if (_meshCurrentlyRunning) return;
    try {
      await _channel.invokeMethod('startMesh');
      _meshCurrentlyRunning = true;
    } on PlatformException catch (e) {
      developer.log('startMesh failed: ${e.message}', name: 'ConnectivityMeshController');
    }
  }

  /// Not called anywhere yet -- kept for the power-saver path
  /// (MeshPolicy.powerSaver already sets allowRelay: false at the Dart
  /// packet-relay layer; stopping the native radios entirely on top of
  /// that is a further battery optimization, not required for MARK I).
  Future<void> stopMesh() async {
    try {
      await _channel.invokeMethod('stopMesh');
      _meshCurrentlyRunning = false;
    } on PlatformException catch (e) {
      developer.log('stopMesh failed: ${e.message}', name: 'ConnectivityMeshController');
    }
  }

  void dispose() {
    _subscription?.cancel();
    _statusController.close();
  }
}
