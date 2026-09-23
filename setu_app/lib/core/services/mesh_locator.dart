import 'dart:developer' as developer;

import 'package:setu_app/features/history/data/repositories/history_repository.dart';
import 'package:setu_app/features/nearby/data/models/nearby_alert_model.dart';
import 'package:setu_app/features/nearby/data/repositories/nearby_repository.dart';
import 'package:setu_app/features/recovery/data/repositories/recovery_repository.dart';
import 'package:setu_app/features/sos/data/models/alert_mode.dart';
import 'package:setu_app/mesh/models/alert_packet.dart';
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
//
// Aug 5 2026: added two persistent listeners here, at the singleton
// level, rather than inside any particular screen's widget lifecycle
// -- both need to work regardless of which screen (if any) is
// currently open, since a real ack or a real incoming community alert
// can arrive at any time, not just while someone's looking at History
// or Nearby Alerts.
//
// 1. acknowledgments listener -- closes the honest-status gap from
//    sos_repository.dart: when a real ack for an emergency THIS device
//    originated arrives, update that history entry from "Sent" to
//    "Delivered" via HistoryRepository, by emergencyId.
//
//    Sep 21 2026 (Vib): also updates RecoveryRepository the same way.
//    A recovery report is signed and sent as an EmergencyPacket (see
//    RecoveryPacketBuilder), so it already gets acked at the protocol
//    level like any other emergency packet -- this just stops
//    discarding that ack for recovery reports specifically. Both
//    lookups are by emergencyId and both are no-ops when nothing
//    matches, so calling both unconditionally on every ack is safe:
//    an ack only ever matches whichever one (history or recovery)
//    actually originated it, since packetIds are unique app-wide.
//
// 2. incomingPackets listener (filtered to AlertPacket) -- this is
//    what makes Nearby Alerts show REAL incoming community alerts
//    from other devices, not just this device's own local copy of its
//    own public SOS. AlertPacket is deliberately anonymous (see its
//    own docstring) -- mapped straight into NearbyAlertModel with no
//    sender-identifying fields carried over.
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

    meshService.acknowledgments.listen((ack) {
      _historyRepository.updateStatusByEmergencyId(ack.emergencyId, 'Delivered');
      _recoveryRepository.updateStatusByEmergencyId(ack.emergencyId, 'Delivered');
    });

    meshService.incomingPackets.listen((packet) {
      if (packet is AlertPacket) {
        _nearbyRepository.addAlert(
          NearbyAlertModel(
            id: packet.packetId,
            alertMode: AlertMode.public,
            latitude: packet.latitude,
            longitude: packet.longitude,
            timestamp: packet.timestamp,
            radius: packet.radiusMeters.toDouble(),
            status: 'ACTIVE',
            incidentType: packet.incidentType,
          ),
        );
      }
    });
  }

  static final MeshLocator instance = MeshLocator._internal();

  /// Block 1 (mesh-stability): called once from main() so the Dart mesh
  /// pipeline exists -- and its native event-channel subscription is
  /// attached -- from process start, instead of the first time the user
  /// happens to open SOS / recovery / readiness. Idempotent: it only
  /// touches the lazy singleton, so exactly one MeshServiceImpl can ever
  /// exist. Needs neither permissions nor internet; it never throws.
  static MeshLocator start() {
    try {
      return instance;
    } catch (e, st) {
      developer.log('Mesh start failed: $e', name: 'MeshLocator', error: e, stackTrace: st);
      rethrow;
    }
  }
  final SigningService signingService;
  final BackendService backendService;
  final NearbyService _nearbyService;
  final LocalQueueService _queueService;
  final HistoryRepository _historyRepository = HistoryRepository();
  final NearbyRepository _nearbyRepository = NearbyRepository();
  final RecoveryRepository _recoveryRepository = RecoveryRepository();
  late final MeshServiceImpl meshService;
}
