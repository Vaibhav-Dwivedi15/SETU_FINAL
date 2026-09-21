import '../../../onboarding/data/services/mesh_permission_service.dart';
import '../../../../core/services/mesh_locator.dart';
import '../../../../services/battery_service.dart';
import '../models/readiness_status.dart';

/// Reuses MeshPermissionService (built for the one-time onboarding gate)
/// and the shared MeshLocator/MeshServiceImpl instance instead of adding
/// a second permission-checking or connection-counting path.
class ReadinessRepository {
  const ReadinessRepository({
    MeshPermissionService? permissionService,
  }) : _permissions = permissionService ?? const MeshPermissionService();

  final MeshPermissionService _permissions;

  Future<ReadinessStatus> check() async {
    final granted = await _permissions.hasAll();
    final bluetoothOn = await _permissions.isBluetoothEnabled();
    final wifiOn = await _permissions.isWifiEnabled();

    return ReadinessStatus(
      permissionsGranted: granted,
      bluetoothEnabled: bluetoothOn,
      wifiEnabled: wifiOn,
      connectedPeers: MeshLocator.instance.meshService.connectedPeerCount,
      batteryLevel: BatteryService.instance.batteryLevel,
    );
  }
}
