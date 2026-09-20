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

  Future<void> dispose() async {
    await _subscription?.cancel();
    await _controller.close();
  }
}