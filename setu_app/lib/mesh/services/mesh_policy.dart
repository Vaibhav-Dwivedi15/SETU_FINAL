import '../../services/power_mode.dart';

class MeshPolicy {
  const MeshPolicy({
    required this.allowRelay,
    required this.allowUpload,
    required this.scanInterval,
    required this.discoveryInterval,
    required this.retryInterval,
  });

  final bool allowRelay;
  final bool allowUpload;

  final Duration scanInterval;
  final Duration discoveryInterval;
  final Duration retryInterval;

  factory MeshPolicy.fromPowerMode(PowerMode mode) {
    switch (mode) {
      case PowerMode.full:
        return const MeshPolicy(
          allowRelay: true,
          allowUpload: true,
          scanInterval: Duration(seconds: 5),
          discoveryInterval: Duration(seconds: 5),
          retryInterval: Duration(seconds: 15),
        );

      case PowerMode.balanced:
        return const MeshPolicy(
          allowRelay: true,
          allowUpload: true,
          scanInterval: Duration(seconds: 15),
          discoveryInterval: Duration(seconds: 15),
          retryInterval: Duration(seconds: 30),
        );

      case PowerMode.powerSaver:
        return const MeshPolicy(
          allowRelay: false,
          allowUpload: false,
          scanInterval: Duration(seconds: 30),
          discoveryInterval: Duration(seconds: 30),
          retryInterval: Duration(seconds: 60),
        );
    }
  }
}