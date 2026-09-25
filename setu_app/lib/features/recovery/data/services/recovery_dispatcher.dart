import 'dart:developer' as developer;

import 'package:setu_app/core/services/mesh_locator.dart';

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

/// Hands a validated report to the transport. Returns the emergencyId of
/// the packet it created (used later to match the acknowledgement).
abstract class RecoveryDispatcher {
  Future<String> dispatch(RecoveryRecord record);
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
  })  : _location = locationService ?? LocationService(),
        _permissions = permissionService ?? const MeshPermissionService(),
        _packetBuilder = packetBuilder ?? RecoveryPacketBuilder();

  final LocationService _location;
  final MeshPermissionService _permissions;
  final RecoveryPacketBuilder _packetBuilder;

  @override
  Future<String> dispatch(RecoveryRecord record) async {
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

    try {
      await MeshLocator.instance.meshService.originate(packet);
    } catch (e) {
      developer.log('Failed to originate recovery report: $e', name: 'MeshRecoveryDispatcher');
      throw RecoveryDispatchException('The mesh could not accept the report: $e');
    }
    return packet.emergencyId;
  }
}
