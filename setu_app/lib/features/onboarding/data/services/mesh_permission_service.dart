import 'dart:developer' as developer;
import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

/// Requests every permission the mesh layer needs to actually run.
///
/// WHY THIS EXISTS (Aug 4 2026 gap analysis): the app declares all the
/// right permissions in AndroidManifest.xml (BLUETOOTH_SCAN,
/// BLUETOOTH_ADVERTISE, BLUETOOTH_CONNECT, NEARBY_WIFI_DEVICES,
/// ACCESS_FINE_LOCATION), but nothing in the Dart layer ever actually
/// requested them at runtime except plain GPS (via LocationService for
/// packet coordinates).
///
/// Aug 5 2026 CRITICAL FIX (Redmi 8A / Android 9 stuck-on-permission-
/// screen bug): the required-permission list was FIXED regardless of
/// Android version, and included Permission.nearbyWifiDevices. That
/// permission (NEARBY_WIFI_DEVICES) only EXISTS on Android 13 (API 33)
/// and up. On older devices (like the Redmi 8A running Android 9),
/// permission_handler reports it as permanently denied/restricted
/// because the OS has no such permission to grant -- so hasAll() could
/// NEVER return true, requestAll() could never clear it, and the
/// permission gate screen looped forever. On Android <13, nearby-Wi-Fi
/// discovery is covered by ACCESS_FINE_LOCATION instead. The fix: build
/// the required list based on the actual Android SDK version, only
/// including nearbyWifiDevices on API 33+.
///
/// `permission_handler` was already a pubspec dependency.
/// `device_info_plus` is needed to read the SDK version -- if it isn't
/// already in pubspec.yaml, add it (`flutter pub add device_info_plus`).
class MeshPermissionService {
  const MeshPermissionService();

  /// Permissions needed on EVERY supported Android version.
  static const List<Permission> _base = [
    Permission.bluetoothScan,
    Permission.bluetoothAdvertise,
    Permission.bluetoothConnect,
    Permission.locationWhenInUse,
  ];

  /// Resolves the actual required list for THIS device's Android version.
  /// nearbyWifiDevices is appended only on API 33+ (Android 13+), where
  /// it actually exists and can be granted. On older versions it's
  /// deliberately omitted -- requesting it there is what caused the
  /// permanent-denied loop.
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
        // If we somehow can't read the SDK version, err on the side of
        // NOT requiring nearbyWifiDevices -- a device that's missing it
        // being wrongly blocked (the original bug) is worse than one
        // that's on API 33+ but skips it (mesh still works via location).
        developer.log('Could not read Android SDK version: $e', name: 'MeshPermission');
      }
    }

    return required;
  }

  /// True only if every required permission (for this device's Android
  /// version) is currently granted.
  Future<bool> hasAll() async {
    final required = await _requiredForThisDevice();
    for (final permission in required) {
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

  /// True if any required permission was permanently denied ("don't ask
  /// again"). Uses the version-aware list, so a non-existent permission
  /// on an older OS can no longer wrongly count as "permanently denied".
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
}
