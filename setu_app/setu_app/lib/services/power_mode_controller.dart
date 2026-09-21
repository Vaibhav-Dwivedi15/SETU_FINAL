import 'dart:async';

import 'battery_service.dart';
import 'power_mode.dart';

class PowerModeController {
  PowerModeController._();

  static final PowerModeController instance = PowerModeController._();

  final StreamController<PowerMode> _controller =
      StreamController<PowerMode>.broadcast();

  StreamSubscription<PowerMode>? _subscription;

  PowerMode _currentMode = PowerMode.full;

  Stream<PowerMode> get stream => _controller.stream;

  PowerMode get currentMode => _currentMode;

  Future<void> initialize() async {
    await BatteryService.instance.initialize();

    _currentMode = BatteryService.instance.currentMode;

    _controller.add(_currentMode);

    _subscription?.cancel();

    _subscription =
        BatteryService.instance.powerModeStream.listen((mode) {
      if (mode == _currentMode) return;

      _currentMode = mode;
      _controller.add(mode);
    });
  }

  /// Sep 2026: stops closing the shared broadcast controller.
  ///
  /// This is a process-wide singleton, but it is disposed by
  /// MeshServiceImpl.dispose() — and the app builds more than one
  /// MeshServiceImpl (MeshLocator and HomeScreen both do). Closing the
  /// controller here meant the FIRST mesh service to be disposed
  /// permanently broke power-mode delivery for every other one: a later
  /// initialize() would hit "Cannot add new events after calling close"
  /// and the surviving mesh service would silently stop reacting to
  /// battery changes — so relay/upload gating would freeze at whatever
  /// mode was last seen.
  ///
  /// Cancelling the upstream subscription is enough to release the
  /// resource. A broadcast controller with no listeners costs nothing,
  /// and leaving it open means initialize() can safely be called again.
  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
  }
}