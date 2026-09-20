import 'dart:async';

import 'package:battery_plus/battery_plus.dart';

import 'power_mode.dart';

class BatteryService {
  BatteryService._();

  static final BatteryService instance = BatteryService._();

  final Battery _battery = Battery();

  final StreamController<PowerMode> _controller =
      StreamController<PowerMode>.broadcast();

  StreamSubscription<BatteryState>? _batterySubscription;

  Stream<PowerMode> get powerModeStream => _controller.stream;

  PowerMode _currentMode = PowerMode.full;

  int _batteryLevel = 100;

  bool _initialized = false;

  int get batteryLevel => _batteryLevel;

  PowerMode get currentMode => _currentMode;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    try {
      _batteryLevel = await _battery.batteryLevel;
      _updateMode(_batteryLevel);

      // Emit current mode immediately.
      _controller.add(_currentMode);

      _batterySubscription =
          _battery.onBatteryStateChanged.listen((_) async {
        final level = await _battery.batteryLevel;

        if (level != _batteryLevel) {
          _batteryLevel = level;
          _updateMode(level);
        }
      });
    } catch (_) {
      // Ignore battery API failures.
    }
  }

  void _updateMode(int level) {
    final PowerMode newMode;

    if (level > 50) {
      newMode = PowerMode.full;
    } else if (level >= 20) {
      newMode = PowerMode.balanced;
    } else {
      newMode = PowerMode.powerSaver;
    }

    if (newMode != _currentMode) {
      _currentMode = newMode;
      _controller.add(newMode);
    }
  }

  Future<void> dispose() async {
    await _batterySubscription?.cancel();
    await _controller.close();
  }
}