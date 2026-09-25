import 'dart:developer' as developer;

import 'package:setu_app/core/services/mesh_locator.dart';
import 'package:setu_app/mesh/models/emergency_packet.dart';
import 'package:setu_app/mesh/services/local_queue_service.dart';

import '../../../location/data/services/location_service.dart';
import '../../../onboarding/data/services/mesh_permission_service.dart';
import '../models/recovery_record.dart';
import 'recovery_packet_builder.dart';

class RecoveryDispatchException implements Exception {
  const RecoveryDispatchException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Called with the emergencyId of the packet as soon as it exists, BEFORE
/// it is handed to the transport, so the caller can persist it. An
/// acknowledgement can only be matched to a report whose emergencyId is
/// already stored.
typedef PacketBuiltCallback = Future<void> Function(String emergencyId);

/// Hands a validated report to the transport. Returns the emergencyId of
/// the packet it created (used later to match the acknowledgement).
abstract class RecoveryDispatcher {
  Future<String> dispatch(RecoveryRecord record, {PacketBuiltCallback? onPacketBuilt});
}

/// The existing store-and-forward path: sign the report as a normal
/// EmergencyPacket and give it to MeshServiceImpl.originate(), which
/// queues it for mesh relay and backend upload with retry. No new packet
/// type and no change to the mesh layer.
///
/// "Dispatch succeeded" therefore means "queued for delivery", never
/// "delivered" -- the caller records it as pending sync.
class MeshRecoveryDispatcher implements RecoveryDispatcher {
  MeshRecoveryDispatcher({
    LocationService? locationService,
    MeshPermissionService? permissionService,
    RecoveryPacketBuilder? packetBuilder,
    Future<void> Function(EmergencyPacket packet)? originate,
    Future<bool> Function(String packetId)? isDurablyQueued,
  })  : _location = locationService ?? LocationService(),
        _permissions = permissionService ?? const MeshPermissionService(),
        _packetBuilder = packetBuilder ?? RecoveryPacketBuilder(),
        _originate = originate ?? _originateOnSharedMesh,
        _isDurablyQueued = isDurablyQueued ?? _isInDurableQueue;

  final LocationService _location;
  final MeshPermissionService _permissions;
  final RecoveryPacketBuilder _packetBuilder;
  final Future<void> Function(EmergencyPacket packet) _originate;
  final Future<bool> Function(String packetId) _isDurablyQueued;

  static Future<void> _originateOnSharedMesh(EmergencyPacket packet) =>
      MeshLocator.instance.meshService.originate(packet);

  static Future<bool> _isInDurableQueue(String packetId) async {
    final pending = await LocalQueueService().getPendingPackets();
    return pending.any((p) => p.packetId == packetId);
  }

  @override
  Future<String> dispatch(RecoveryRecord record, {PacketBuiltCallback? onPacketBuilt}) async {
    if (!await _permissions.hasAll()) {
      final stillMissing = await _permissions.requestAll();
      if (stillMissing.isNotEmpty) {
        throw const RecoveryDispatchException(
          'SETU needs Bluetooth, Wi-Fi and location permissions to send this '
          'report without internet.',
        );
      }
    }

    // The packet format requires coordinates; use the fix the user
    // captured on the form, else take one now.
    double? latitude = record.latitude;
    double? longitude = record.longitude;
    if (latitude == null || longitude == null) {
      try {
        final fix = await _location.getCurrentLocation();
        latitude = fix.latitude;
        longitude = fix.longitude;
      } catch (e) {
        throw RecoveryDispatchException(
            'Could not get the device location. ${e.toString().replaceFirst('Exception: ', '')}');
      }
    }

    final packet = await _packetBuilder.buildRecoveryPacket(
      type: record.type,
      latitude: latitude,
      longitude: longitude,
      message: record.toPacketMessage(),
      priority: record.packetPriority,
    );
    await onPacketBuilt?.call(packet.emergencyId);

    try {
      await _originate(packet);
    } catch (e) {
      // MeshServiceImpl.originate() writes the packet to the durable
      // upload queue BEFORE it hands it to the native radio, and the
      // native call can fail on its own (e.g. the mesh service is not
      // bound yet). If the packet is already queued, the backend upload
      // sweep will still deliver it, so reporting "failed" here would
      // invite a Retry that sends the same report a second time.
      var queued = false;
      try {
        queued = await _isDurablyQueued(packet.packetId);
      } catch (_) {
        // Cannot tell: report the failure rather than assume delivery.
      }
      if (queued) {
        developer.log(
          'Radio hand-off failed but packet is durably queued; treating as queued: $e',
          name: 'MeshRecoveryDispatcher',
        );
        return packet.emergencyId;
      }
      developer.log('Failed to originate recovery report: $e', name: 'MeshRecoveryDispatcher');
      throw RecoveryDispatchException('The mesh could not accept the report: $e');
    }
    return packet.emergencyId;
  }
}
