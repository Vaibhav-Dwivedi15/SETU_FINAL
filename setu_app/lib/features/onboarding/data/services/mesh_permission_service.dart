import 'dart:developer' as developer;
import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

/// Requests every permission the mesh layer needs to actually run.
///
/// WHY THIS EXISTS (Aug 4 2026 gap analysis): the app declares all the
/// right permissions in AndroidManifest.xml, but nothing in the Dart
/// layer ever actually requested them at runtime.
///
/// Aug 5 2026 CRITICAL FIX (Redmi 8A / Android 9 stuck-on-permission-
/// screen bug): Permission.nearbyWifiDevices only EXISTS on Android 13
/// (API 33) and up. On older devices, permission_handler reports it as
/// permanently denied/restricted, so the required-permission list is
/// now built per Android SDK version.
///
/// Aug 5 2026 ALSO ADDED: radio-state checks (Bluetooth/Wi-Fi actually
/// ON, not just "permission granted"). On Android <12, Bluetooth
/// runtime permissions don't exist at all -- the OS silently
/// auto-grants the old install-time BLUETOOTH/BLUETOOTH_ADMIN
/// permissions with NO dialog ever shown. That's correct Android
/// behavior, but it means "permission granted" alone tells you nothing
/// about whether the user's Bluetooth radio is actually switched on --
/// and that gap exists on EVERY Android version, not just old ones.
/// hasRadiosReady()/promptEnableRadios() check/prompt the actual radio
/// state via the native `setu/radio_state` channel (see
/// RadioStateChannelHandler.kt), so behavior is identical regardless
/// of which Android version a given user's phone happens to run --
/// the team doesn't need to know in advance which OS version any
/// future user has.
class MeshPermissionService {
  const MeshPermissionService();

  static const MethodChannel _radioChannel = MethodChannel('setu/radio_state');

  static const List<Permission> _base = [
    Permission.bluetoothScan,
    Permission.bluetoothAdvertise,
    Permission.bluetoothConnect,
    Permission.locationWhenInUse,
  ];

  Future<List<Permission>> _requiredForThisDevice() async {
    final required = List<Permission>.from(_base);

    if (Platform.isAndroid) {
      try {
        final info = await DeviceInfoPlugin().androidInfo;
        final sdkInt = info.version.sdkInt;
        developer.log('Android SDK version: $sdkInt', name: 'MeshPermission');
        if (sdkInt >= 33) {
          required.add(Permission.nearbyWifiDevices);
        } else {
          developer.log(
            'Skipping nearbyWifiDevices (Android <13, covered by location)',
            name: 'MeshPermission',
          );
        }
      } catch (e) {
        developer.log('Could not read Android SDK version: $e', name: 'MeshPermission');
      }
    }

    return required;
  }

  Future<bool> hasAll() async {
    final required = await _requiredForThisDevice();
    for (final permission in required) {
      final status = await permission.status;
      developer.log('hasAll() check: $permission -> $status', name: 'MeshPermission');
      if (!status.isGranted) return false;
    }
    return true;
  }

  Future<List<Permission>> requestAll() async {
    final required = await _requiredForThisDevice();
    final stillMissing = <Permission>[];
    for (final permission in required) {
      try {
        final currentStatus = await permission.status;
        developer.log('requestAll() pre-check: $permission -> $currentStatus', name: 'MeshPermission');

        if (currentStatus.isGranted) {
          developer.log('requestAll() skip (already granted): $permission', name: 'MeshPermission');
          continue;
        }

        developer.log('requestAll() requesting: $permission', name: 'MeshPermission');
        final result = await permission.request();
        developer.log('requestAll() result: $permission -> $result', name: 'MeshPermission');

        if (!result.isGranted) {
          stillMissing.add(permission);
        }
      } catch (e, stack) {
        developer.log(
          'requestAll() EXCEPTION for $permission: $e',
          name: 'MeshPermission',
          error: e,
          stackTrace: stack,
        );
        stillMissing.add(permission);
      }
    }
    developer.log('requestAll() final stillMissing: $stillMissing', name: 'MeshPermission');
    return stillMissing;
  }

  Future<bool> anyPermanentlyDenied() async {
    final required = await _requiredForThisDevice();
    for (final permission in required) {
      final status = await permission.status;
      final permanentlyDenied = status.isPermanentlyDenied;
      developer.log(
        'anyPermanentlyDenied() check: $permission -> $status (permanentlyDenied=$permanentlyDenied)',
        name: 'MeshPermission',
      );
      if (permanentlyDenied) return true;
    }
    return false;
  }

  Future<void> openSettings() => openAppSettings();

  /// True only if Bluetooth is actually switched ON. Version-proof --
  /// works identically on Android 9 through the latest release, unlike
  /// the permission_handler Bluetooth permissions which only exist as
  /// a runtime concept on API 31+.
  Future<bool> isBluetoothEnabled() async {
    if (!Platform.isAndroid) return true;
    try {
      final enabled = await _radioChannel.invokeMethod<bool>('isBluetoothEnabled');
      developer.log('isBluetoothEnabled() -> $enabled', name: 'MeshPermission');
      return enabled ?? false;
    } catch (e) {
      developer.log('isBluetoothEnabled() failed: $e', name: 'MeshPermission');
      return false;
    }
  }

  /// Shows the system "Turn on Bluetooth?" dialog if it's off. Returns
  /// true if it's on afterward (either it already was, or the user
  /// tapped Allow). This dialog is available on every Android version
  /// SETU supports -- unlike runtime BLUETOOTH_SCAN etc., which is an
  /// Android 12+-only concept.
  Future<bool> promptEnableBluetooth() async {
    if (!Platform.isAndroid) return true;
    try {
      final enabled = await _radioChannel.invokeMethod<bool>('requestEnableBluetooth');
      developer.log('promptEnableBluetooth() -> $enabled', name: 'MeshPermission');
      return enabled ?? false;
    } catch (e) {
      developer.log('promptEnableBluetooth() failed: $e', name: 'MeshPermission');
      return false;
    }
  }

  Future<bool> isWifiEnabled() async {
    if (!Platform.isAndroid) return true;
    try {
      final enabled = await _radioChannel.invokeMethod<bool>('isWifiEnabled');
      developer.log('isWifiEnabled() -> $enabled', name: 'MeshPermission');
      return enabled ?? false;
    } catch (e) {
      developer.log('isWifiEnabled() failed: $e', name: 'MeshPermission');
      return false;
    }
  }

  /// Opens the system Wi-Fi settings panel. Android 10+ blocks apps
  /// from directly toggling Wi-Fi programmatically (WifiManager's
  /// setEnabled() silently no-ops there) -- opening system settings is
  /// the correct, version-safe action so the user can turn it on
  /// themselves, on any Android version.
  Future<void> openWifiSettings() async {
    if (!Platform.isAndroid) return;
    try {
      await _radioChannel.invokeMethod('openWifiSettings');
    } catch (e) {
      developer.log('openWifiSettings() failed: $e', name: 'MeshPermission');
    }
  }
}
