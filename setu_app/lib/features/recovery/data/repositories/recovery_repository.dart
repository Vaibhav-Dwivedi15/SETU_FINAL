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
// NOT DONE THIS PHASE (documented, not silently skipped): unlike SOS,
// a recovery report's delivery status is never upgraded from "Sent" to
// "Delivered" via an AckPacket -- MeshLocator's existing ack listener
// only updates HistoryRepository entries by emergencyId
// (see mesh_locator.dart), and RecoveryReportModel is a separate,
// simpler local record deliberately not wired into that listener this
// phase. A recovery report still gets acked at the protocol level
// (MeshServiceImpl._originateAck acks any received EmergencyPacket
// indiscriminately) -- only the LOCAL UI-visible status stays at
// "Sent". Wiring that up is a small, safe follow-up, not attempted
// here to keep this phase's diff additive and reviewable.
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
    );

    await _log.addEntry(record);
    return record;
  }
}
