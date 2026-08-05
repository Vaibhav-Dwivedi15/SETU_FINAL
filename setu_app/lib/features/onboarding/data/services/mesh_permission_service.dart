import 'dart:developer' as developer;

import 'package:permission_handler/permission_handler.dart';

/// Requests every permission the mesh layer needs to actually run.
///
/// WHY THIS EXISTS (Aug 4 2026 gap analysis): the app declares all the
/// right permissions in AndroidManifest.xml (BLUETOOTH_SCAN,
/// BLUETOOTH_ADVERTISE, BLUETOOTH_CONNECT, NEARBY_WIFI_DEVICES,
/// ACCESS_FINE_LOCATION), but nothing in the Dart layer ever actually
/// requested them at runtime except plain GPS (via LocationService for
/// packet coordinates). On a real Android 12+ device that means the
/// mesh layer silently can't advertise/discover/connect until the OS
/// permission dialogs are triggered from somewhere -- and nothing did.
///
/// `permission_handler` was already a pubspec dependency, just unused
/// for this. No new package needed.
///
/// Aug 5 2026: added explicit per-permission logging (developer.log)
/// throughout, because the plugin's own logcat output ("No permissions
/// found in manifest for: []") gives zero indication of WHICH permission
/// is involved or what its actual status/result is -- not enough to
/// diagnose a stuck permission gate on a real device (Redmi 8A, Android
/// 9). This makes every step visible in `adb logcat -s MeshPermission`.
class MeshPermissionService {
  const MeshPermissionService();

  /// Every permission the mesh + location layers need together.
  /// Kept as one list (not split per-feature) because a phone that's
  /// missing any one of these can't function as a relay node at all --
  /// there's no useful partial-permission state for this app's core
  /// purpose.
  static const List<Permission> _required = [
    Permission.bluetoothScan,
    Permission.bluetoothAdvertise,
    Permission.bluetoothConnect,
    Permission.nearbyWifiDevices,
    Permission.locationWhenInUse,
  ];

  /// True only if every required permission is currently granted.
  Future<bool> hasAll() async {
    for (final permission in _required) {
      final status = await permission.status;
      developer.log('hasAll() check: $permission -> $status', name: 'MeshPermission');
      if (!status.isGranted) return false;
    }
    return true;
  }

  /// Requests every missing permission, in order, and returns whichever
  /// ones are STILL not granted afterward (empty list = all granted).
  ///
  /// Requesting sequentially (not Future.wait in parallel) is deliberate:
  /// Android's permission dialogs queue and can behave inconsistently if
  /// several system dialogs are triggered at once from a single frame.
  Future<List<Permission>> requestAll() async {
    final stillMissing = <Permission>[];
    for (final permission in _required) {
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
        // A permission_handler call throwing on a specific OS version/
        // permission combo would previously have been silently lost --
        // no try/catch existed here before. Treat any exception as
        // "still missing" rather than letting it crash requestAll()
        // partway through and leave later permissions unrequested.
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

  /// True if any missing permission was permanently denied ("don't ask
  /// again") -- at that point re-requesting does nothing and the only
  /// path forward is the OS app settings screen.
  Future<bool> anyPermanentlyDenied() async {
    for (final permission in _required) {
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
}
