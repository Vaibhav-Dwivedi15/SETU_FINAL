import 'package:setu_app/features/preparedness/data/services/preparedness_service.dart';

/// Offline recovery guidance (unsafe buildings, electrical hazards, ...),
/// bundled in assets/recovery/recovery_guidance.json and loaded with the
/// same cached, failure-tolerant loader as the preparedness guides.
abstract final class RecoveryGuidanceService {
  static final GuideLibrary instance = GuideLibrary(
    assetPath: 'assets/recovery/recovery_guidance.json',
    listKey: 'topics',
  );
}
