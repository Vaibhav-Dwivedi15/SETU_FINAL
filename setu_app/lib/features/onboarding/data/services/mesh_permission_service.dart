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
      if (!await permission.status.isGranted) return false;
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
      if (await permission.status.isGranted) continue;

      final result = await permission.request();
      if (!result.isGranted) {
        stillMissing.add(permission);
      }
    }

    return stillMissing;
  }

  /// True if any missing permission was permanently denied ("don't ask
  /// again") -- at that point re-requesting does nothing and the only
  /// path forward is the OS app settings screen.
  Future<bool> anyPermanentlyDenied() async {
    for (final permission in _required) {
      if (await permission.status.isPermanentlyDenied) return true;
    }
    return false;
  }

  Future<void> openSettings() => openAppSettings();
}
