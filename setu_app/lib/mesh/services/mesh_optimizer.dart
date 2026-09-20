import '../../services/power_mode.dart';
import 'connection_quality.dart';
import 'mesh_policy.dart';

class MeshOptimizer {
  const MeshOptimizer();

  MeshPolicy policyFor({
    required PowerMode powerMode,
    required ConnectionQuality quality,
  }) {
    switch (quality) {
      case ConnectionQuality.excellent:
        return MeshPolicy.fromPowerMode(powerMode);

      case ConnectionQuality.good:
        return MeshPolicy.fromPowerMode(powerMode);

      case ConnectionQuality.fair:
        return MeshPolicy(
          allowRelay: true,
          allowUpload: true,
          scanInterval: const Duration(seconds: 20),
          discoveryInterval: const Duration(seconds: 20),
          retryInterval: const Duration(seconds: 45),
        );

      case ConnectionQuality.poor:
        return MeshPolicy(
          allowRelay: true,
          allowUpload: true,
          scanInterval: const Duration(seconds: 30),
          discoveryInterval: const Duration(seconds: 30),
          retryInterval: const Duration(seconds: 60),
        );
    }
  }
}