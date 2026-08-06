import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/services.dart';

import 'package:setu_app/core/services/mesh_locator.dart';

import '../../../contacts/data/repositories/contact_repository.dart';
import '../../../history/data/models/history_model.dart';
import '../../../history/data/repositories/history_repository.dart';
import '../../../location/data/services/location_service.dart';
import '../../../onboarding/data/services/mesh_permission_service.dart';
import '../../../sms/data/repositories/sms_repository.dart';
import '../../../nearby/data/models/nearby_alert_model.dart';
import '../../../nearby/data/repositories/nearby_repository.dart';
import '../models/alert_mode.dart';
import '../models/emergency_category.dart';
import '../services/alert_packet_builder.dart';
import '../services/emergency_packet_builder.dart';
import 'package:setu_app/services/backend_service.dart';

enum SosProgress {
  checkingNetwork,
  networkUnavailable,
  activatingMesh,
  searchingRelayDevices,
  forwarding,
  onlineSending,
  backendConfirmed,
  notifyingContacts,
  delivered,
  failed,
}

class SosRepository {
  final ContactRepository _contactRepository = ContactRepository();
  final LocationService _locationService = LocationService();
  final SmsRepository _smsRepository = SmsRepository();
  final HistoryRepository _historyRepository = HistoryRepository();
  final NearbyRepository _nearbyRepository = NearbyRepository();
  final MeshPermissionService _permissionService = const MeshPermissionService();
  final EmergencyPacketBuilder _emergencyPacketBuilder = EmergencyPacketBuilder();
  final AlertPacketBuilder _alertPacketBuilder = AlertPacketBuilder();
  final BackendService _backendService = BackendService();

  static const MethodChannel _meshChannel = MethodChannel('com.setu.mesh/methods');

  static final _progressController = StreamController<SosProgress>.broadcast();
  static Stream<SosProgress> get progressStream => _progressController.stream;

  Future<void> triggerSOS({
    required AlertMode alertMode,
    EmergencyCategory category = EmergencyCategory.generalSos,
  }) async {
    if (!await _permissionService.hasAll()) {
      final stillMissing = await _permissionService.requestAll();
      if (stillMissing.isNotEmpty) {
        _progressController.add(SosProgress.failed);
        throw Exception(
          "SETU needs Bluetooth, Wi-Fi and location permissions to relay "
          "your SOS without internet. Please allow them and try again.",
        );
      }
    }

    final contacts = await _contactRepository.getContacts();

    if (contacts.isEmpty) {
      _progressController.add(SosProgress.failed);
      throw Exception(
        "No emergency contacts found. Please add at least one contact.",
      );
    }

    final location = await _locationService.getCurrentLocation();
    final phoneNumbers = contacts.map((e) => e.phone).toList();
    final mapsLink =
        "https://maps.google.com/?q=${location.latitude},${location.longitude}";
    final modeName = alertMode == AlertMode.private
        ? "PRIVATE SOS"
        : "PUBLIC SOS";
    final message =
        '''
🚨 $modeName — ${category.title} 🚨

${category.alertHeading}

Latitude : ${location.latitude}
Longitude: ${location.longitude}

Google Maps:
$mapsLink
''';

    int retryCount = 0;
    String status = "Sent";
    String errorReason = "";
    String emergencyId = "";
    // Aug 5 2026 fix: SMS failure (e.g. true airplane mode -- SmsManager
    // needs the cellular voice/SMS radio, which airplane mode disables
    // entirely and no app-level code can override) was previously
    // UNCAUGHT here, so it propagated to the outer catch block and
    // marked the ENTIRE SOS as "Failed" -- even when the emergency
    // packet had already been successfully originated onto the mesh
    // moments earlier. That's actively misleading: the mesh signal
    // genuinely went out; only the LOCAL SMS attempt (a redundant,
    // best-effort channel -- the backend's own SMS Gateway is the real
    // fallback for a device with zero cellular capability, see
    // handoff docs) failed. Mesh success and SMS success are now
    // tracked independently -- SMS failing degrades the status
    // message but does NOT overwrite an already-successful mesh send
    // with "Failed", and does NOT throw/abort the rest of the flow
    // (public alert broadcast still happens even if SMS failed).
    bool smsFailed = false;
    String smsFailureReason = "";

    try {
      _progressController.add(SosProgress.checkingNetwork);
      final hasInternet = await _backendService.hasRealInternet();

      if (!hasInternet) {
        _progressController.add(SosProgress.networkUnavailable);
        await Future<void>.delayed(const Duration(milliseconds: 600));
        _progressController.add(SosProgress.activatingMesh);
        await Future<void>.delayed(const Duration(milliseconds: 600));
        _progressController.add(SosProgress.searchingRelayDevices);
      } else {
        _progressController.add(SosProgress.onlineSending);
      }

      final emergencyPacket = await _emergencyPacketBuilder.buildEmergencyPacket(
        latitude: location.latitude,
        longitude: location.longitude,
        message: message,
        category: category,
      );
      emergencyId = emergencyPacket.emergencyId;

      // If THIS line throws, the SOS genuinely failed end-to-end --
      // that's correctly caught by the outer try/catch below and marks
      // status "Failed", same as before. Everything after this point
      // is secondary/redundant channels (SMS, public broadcast) whose
      // individual failure should NOT retroactively undo this success.
      await MeshLocator.instance.meshService.originate(emergencyPacket);
      developer.log('Emergency packet originated onto mesh: $emergencyId', name: 'SosRepository');

      if (!hasInternet) {
        _progressController.add(SosProgress.forwarding);
      } else {
        try {
          final confirmed = await _backendService
              .uploadPacket(emergencyPacket)
              .timeout(const Duration(seconds: 10), onTimeout: () => false);
          if (confirmed) {
            _progressController.add(SosProgress.backendConfirmed);
            status = "Delivered";
          }
        } catch (_) {
          // status stays "Sent" -- packet is safely queued regardless.
        }
      }

      try {
        await _meshChannel.invokeMethod('updateLocation', {
          'latitude': location.latitude,
          'longitude': location.longitude,
        });
      } catch (_) {}

      if (hasInternet) {
        _progressController.add(SosProgress.notifyingContacts);
      }

      // Aug 5 2026 fix: SMS is now its own try/catch, isolated from the
      // rest of the flow. A failure here (most commonly: no cellular
      // radio available, e.g. true airplane mode, or the device has no
      // SIM) is recorded for the history entry's errorReason but does
      // NOT throw -- the mesh packet already went out above, and the
      // public alert broadcast below should still happen regardless of
      // whether the local SMS channel worked.
      try {
        await _smsRepository.sendBulkSMS(
          message: message,
          phoneNumbers: phoneNumbers,
        );
      } catch (e) {
        smsFailed = true;
        smsFailureReason = e.toString().replaceFirst("Exception: ", "");
        developer.log(
          'SMS failed but mesh packet already sent -- not failing overall SOS: $smsFailureReason',
          name: 'SosRepository',
        );
      }

      if (alertMode == AlertMode.public) {
        await _nearbyRepository.addAlert(
          NearbyAlertModel(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            alertMode: alertMode,
            latitude: location.latitude,
            longitude: location.longitude,
            timestamp: DateTime.now(),
            radius: 1000,
            status: "ACTIVE",
          ),
        );

        final alertPacket = await _alertPacketBuilder.buildAlertPacket(
          incidentType: category.name,
          latitude: location.latitude,
          longitude: location.longitude,
        );
        await MeshLocator.instance.meshService.originate(alertPacket);
      }

      if (smsFailed) {
        errorReason = "Emergency signal sent via mesh. SMS to contacts "
            "failed: $smsFailureReason";
      }

      _progressController.add(SosProgress.delivered);
    } catch (e) {
      status = "Failed";
      retryCount = 3;
      errorReason = e.toString();

      _progressController.add(SosProgress.failed);
      rethrow;
    } finally {
      await _historyRepository.addHistory(
        HistoryModel(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          timestamp: DateTime.now(),
          latitude: location.latitude,
          longitude: location.longitude,
          recipients: phoneNumbers,
          status: status,
          message: message,
          mapsLink: mapsLink,
          alertMode: alertMode,
          retryCount: retryCount,
          errorReason: errorReason,
          locationAttached: true,
          emergencyId: emergencyId,
        ),
      );
    }
  }
}
