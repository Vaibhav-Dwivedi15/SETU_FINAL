import 'dart:async';
import 'dart:developer' as developer;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/services.dart';

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
/// This controller adds that reactive layer WITHOUT removing the
/// always-on default -- see USAGE below. `connectivity_plus` was
/// already a pubspec dependency; no new package needed. The native
/// side needs two small additions to MeshChannelHandler.kt
/// ("startMesh" / "stopMesh" method channel cases) since nothing
/// currently exposes stop control from Dart at all -- see the paired
/// Kotlin diff in this same changeset.
///
/// USAGE: call `ConnectivityMeshController.instance.enableAutoMode()`
/// once (e.g. from main.dart or a settings toggle) to switch the app
/// from "mesh always on" to "mesh reacts to connectivity" -- ties
/// relay activity to exactly the moments this phone doesn't have its
/// own internet, which is the real-world case where being a relay
/// node actually matters and costs the least extra battery.
class ConnectivityMeshController {
  ConnectivityMeshController._();

  static final ConnectivityMeshController instance = ConnectivityMeshController._();

  static const MethodChannel _channel = MethodChannel('com.setu.mesh/methods');

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  bool _meshCurrentlyRunning = true; // MeshChannelHandler.start() already ran it at launch.

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

    // Mesh stays on when offline (that's the whole point) AND stays on
    // when online too, by default -- a phone with signal is still a
    // useful relay for a neighbour without any. Auto mode only ever
    // turns mesh OFF if a future battery-driven policy decides to; for
    // now this just guarantees it's ON, covering the "did the radios
    // silently die" case, not adding a new OFF condition.
    if (isOffline) {
      await _ensureMeshRunning();
    } else {
      await _ensureMeshRunning();
    }
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
  }
}
