// =====================================================
// SETU Project
// Module : Volume-Button SOS Shortcut (Block 29/31)
// Owner  : Sudheer
// =====================================================
//
// WHY VOLUME BUTTONS, NOT POWER: Android does not expose
// power-button press events to third-party apps at all — the
// OS's own "5x power button = Emergency SOS" is a SystemUI
// feature, not a public API (confirmed: Samsung's own developer
// forum states this explicitly). Volume keys are the closest
// hardware-button shortcut actually achievable from app code.
//
// HONEST LIMITATION: this only fires while the app process is
// alive (foreground, or backgrounded but not killed by the OS).
//
// Block 31: added a debug SnackBar on every press received, so
// "it's not working" can be diagnosed — if the SnackBar never
// appears when you press Volume Down, the native channel isn't
// firing at all (check MainActivity.kt was actually applied on
// device, and that the app was rebuilt after that change — a
// hot reload does NOT pick up native code changes, only a full
// rebuild does). If the SnackBar DOES appear but SOS doesn't
// fire, the problem is downstream (contacts/location/SMS), not
// the button detection.
//
// Double-press Volume Down (within ~1s) -> Private SOS.
// Triple-press Volume Down (within ~2s) -> Public SOS.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:setu_app/app.dart';
import 'package:setu_app/features/sos/data/models/alert_mode.dart';
import 'package:setu_app/features/sos/data/repositories/sos_repository.dart';

class VolumeButtonSosService {
  VolumeButtonSosService._internal();

  static final VolumeButtonSosService instance =
      VolumeButtonSosService._internal();

  static const MethodChannel _channel = MethodChannel('setu/volume_keys');

  final SosRepository _sosRepository = SosRepository();

  final List<DateTime> _pressTimestamps = [];
  Timer? _decisionTimer;
  bool _initialized = false;

  void initialize() {
    if (_initialized) return;
    _initialized = true;
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    if (call.method == 'volumeDownPressed') {
      _onVolumeDownPressed();
    }
  }

  void _showDebugToast(String message) {
    rootScaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 1)),
    );
  }

  void _onVolumeDownPressed() {
    final now = DateTime.now();

    _pressTimestamps.removeWhere(
      (t) => now.difference(t) > const Duration(seconds: 2),
    );
    _pressTimestamps.add(now);

    _showDebugToast('Volume press ${_pressTimestamps.length}/3 detected');

    _decisionTimer?.cancel();

    if (_pressTimestamps.length >= 3) {
      _pressTimestamps.clear();
      _trigger(AlertMode.public);
      return;
    }

    if (_pressTimestamps.length == 2) {
      _decisionTimer = Timer(const Duration(milliseconds: 500), () {
        if (_pressTimestamps.length == 2) {
          _pressTimestamps.clear();
          _trigger(AlertMode.private);
        }
      });
    }
  }

  Future<void> _trigger(AlertMode mode) async {
    HapticFeedback.heavyImpact();
    _showDebugToast('Triggering ${mode.name} SOS...');

    try {
      await _sosRepository.triggerSOS(alertMode: mode);
    } catch (e) {
      _showDebugToast('SOS failed: $e');
    }
  }
}
