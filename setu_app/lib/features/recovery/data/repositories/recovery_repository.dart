import 'dart:developer' as developer;

import 'package:setu_app/core/services/mesh_locator.dart';

import '../../../location/data/services/location_service.dart';
import '../../../onboarding/data/services/mesh_permission_service.dart';
import '../models/recovery_report_model.dart';
import '../models/recovery_report_type.dart';
import '../services/recovery_log_service.dart';
import '../services/recovery_packet_builder.dart';

// =====================================================
// SETU Project
// Module : Recovery (AFTER-disaster) repository
// Priority 8 (session brief)
// =====================================================
//
// Reuses, does not duplicate: MeshLocator's single shared
// MeshServiceImpl instance (same one SOS/nearby-alerts/readiness-check
// all use), MeshPermissionService (onboarding's permission gate),
// LocationService (SOS's own location lookup), and
// MeshServiceImpl.originate() itself -- which already does signing-
// independent bookkeeping (store-and-forward enqueue, backend upload
// retry, RelayLogRepository entry, MeshMetrics) for ANY MeshPacket, not
// just EmergencyPacket-as-SOS. A recovery report gets that entire
// pipeline for free because it IS an EmergencyPacket (see
// RecoveryPacketBuilder's own docstring for why).
//
// UPDATE (Vib, mesh/architecture): the "Sent" status is now upgraded to
// "Delivered" the same way SOS history is -- MeshLocator's existing
// acknowledgments listener now also calls
// updateStatusByEmergencyId() below, matching on the emergencyId the
// signed EmergencyPacket carried (see RecoveryPacketBuilder, which
// sets emergencyId: packetId). Purely additive: no new PacketType, no
// signature-payload change, no change to MeshServiceImpl's relay/ack
// origination logic -- only the local bookkeeping this repository and
// RecoveryLogService already owned. The mesh/packet layer was already
// acking every EmergencyPacket indiscriminately
// (MeshServiceImpl._originateAck); this change only makes the LOCAL
// UI-visible status reflect that real ack instead of staying
// optimistically at "Sent" forever.
//
// Known remaining gap: only two states are tracked end-to-end today,
// "Sent" and "Delivered" -- the three-state target from the project
// overview ("Sent -> Relayed -> Delivered") needs a per-hop relay
// event that nothing in the mesh layer currently emits (SOS/History
// doesn't have it either). Not attempted here; would need a new,
// explicit relay-observed signal, not something to fake from existing
// data.
class RecoveryRepository {
  RecoveryRepository({
    LocationService? locationService,
    MeshPermissionService? permissionService,
    RecoveryPacketBuilder? packetBuilder,
    RecoveryLogService? logService,
  })  : _location = locationService ?? LocationService(),
        _permissions = permissionService ?? const MeshPermissionService(),
        _packetBuilder = packetBuilder ?? RecoveryPacketBuilder(),
        _log = logService ?? RecoveryLogService();

  final LocationService _location;
  final MeshPermissionService _permissions;
  final RecoveryPacketBuilder _packetBuilder;
  final RecoveryLogService _log;

  Future<List<RecoveryReportModel>> getReports() => _log.getLog();

  /// Sends one recovery report over the mesh and records it locally.
  /// Throws if mesh permissions aren't granted or location can't be
  /// resolved -- same failure contract as SosRepository.triggerSOS, so
  /// the calling screen can show the same kind of error UI.
  Future<RecoveryReportModel> submitReport({
    required RecoveryReportType type,
    required String message,
  }) async {
    if (!await _permissions.hasAll()) {
      final stillMissing = await _permissions.requestAll();
      if (stillMissing.isNotEmpty) {
        throw Exception(
          'SETU needs Bluetooth, Wi-Fi and location permissions to send '
          'this report without internet. Please allow them and try again.',
        );
      }
    }

    final location = await _location.getCurrentLocation();

    final packet = await _packetBuilder.buildRecoveryPacket(
      type: type,
      latitude: location.latitude,
      longitude: location.longitude,
      message: message,
    );

    try {
      await MeshLocator.instance.meshService.originate(packet);
    } catch (e) {
      developer.log('Failed to originate recovery report: $e', name: 'RecoveryRepository');
      rethrow;
    }

    final record = RecoveryReportModel(
      id: packet.packetId,
      type: type,
      message: message,
      latitude: location.latitude,
      longitude: location.longitude,
      timestamp: DateTime.now(),
      // Explicit rather than relying on the model's id-fallback, since
      // this is the one place that actually knows the packet's real
      // emergencyId (== packetId, see RecoveryPacketBuilder) -- keeps
      // the two in sync by construction instead of by coincidence.
      emergencyId: packet.emergencyId,
    );

    await _log.addEntry(record);
    return record;
  }

  /// Exposed so MeshLocator's ack listener can update a recovery
  /// report's status without reaching past the repository layer --
  /// mirrors HistoryRepository.updateStatusByEmergencyId exactly.
  Future<void> updateStatusByEmergencyId(String emergencyId, String newStatus) async {
    await _log.updateStatusByEmergencyId(emergencyId, newStatus);
  }
}
