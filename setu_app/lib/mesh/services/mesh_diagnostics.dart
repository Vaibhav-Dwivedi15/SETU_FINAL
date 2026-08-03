import 'mesh_health.dart';
import 'mesh_logger.dart';

class MeshDiagnostics {
  const MeshDiagnostics();

  void run(MeshHealth health) {
    if (health.healthy) {
      MeshLogger.info('Mesh Status : Healthy');
      return;
    }

    if (health.connectedPeers == 0) {
      MeshLogger.warning('No nearby peers connected.');
    }

    if (health.pendingUploads > 100) {
      MeshLogger.warning('Upload queue growing.');
    }

    if (health.pendingRelay > 100) {
      MeshLogger.warning('Relay queue growing.');
    }

    if (health.batteryLevel <= 20) {
      MeshLogger.warning('Battery saver mode active.');
    }
  }
}