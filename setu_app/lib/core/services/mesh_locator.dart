import 'package:setu_app/mesh/services/local_queue_service.dart';
import 'package:setu_app/mesh/services/mesh_service.dart';
import 'package:setu_app/mesh/services/nearby_service.dart';
import 'package:setu_app/mesh/services/signing_service.dart';
import 'package:setu_app/services/backend_service.dart';

// =====================================================
// SETU Project
// Module : Mesh service locator (SOS-to-mesh wiring)
// =====================================================
//
// One shared MeshServiceImpl instance for the whole app, so the SOS
// flow, the mesh's own upload retry loop, and the responder registry
// sync all operate on the same instance instead of duplicating state.
//
// NearbyService is abstract — PlatformNearbyService is the concrete
// implementation, confirmed via grep. BackendService()'s baseUrl still
// defaults to a placeholder URL (backend_service.dart) — update once
// Ayush's backend is deployed and the real URL is known.
class MeshLocator {
  MeshLocator._internal()
      : signingService = SigningService(),
        backendService = BackendService(),
        _nearbyService = PlatformNearbyService(),
        _queueService = LocalQueueService() {
    meshService = MeshServiceImpl(
      nearbyService: _nearbyService,
      signingService: signingService,
      backendService: backendService,
      queueService: _queueService,
    );
  }

  static final MeshLocator instance = MeshLocator._internal();

  final SigningService signingService;
  final BackendService backendService;
  final NearbyService _nearbyService;
  final LocalQueueService _queueService;
  late final MeshServiceImpl meshService;
}
