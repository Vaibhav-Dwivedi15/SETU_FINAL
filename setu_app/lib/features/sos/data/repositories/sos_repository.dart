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

    // Aug 6 2026 fix: mesh origination and SMS are now BOTH isolated,
    // independently. Previously only SMS had its own try/catch (fixed
    // earlier today) -- but MeshLocator.instance.meshService.originate()
    // itself was still unprotected. If IT threw for any reason (native
    // channel error, mesh internal state issue), the exception jumped
    // straight to the outer catch block and skipped EVERYTHING after
    // it in the sequence, including the SMS attempt below -- meaning a
    // mesh-layer hiccup could silently prevent SMS from ever being
    // tried at all. That's the most likely explanation for "SMS only
    // sends when internet is present": a no-internet-but-has-cellular
    // scenario is exactly when the mesh layer's own state/behavior
    // changes the most, so a mesh-side exception there was aborting
    // the SMS attempt too. Now each channel is attempted independently
    // -- a failure in one is recorded but does not prevent the other
    // from being tried.
    bool meshFailed = false;
    String meshFailureReason = "";
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

      // Mesh origination: isolated. A failure here is recorded but no
      // longer prevents SMS (below) or the public broadcast from being
      // attempted.
      try {
        await MeshLocator.instance.meshService.originate(emergencyPacket);
        developer.log('Emergency packet originated onto mesh: $emergencyId', name: 'SosRepository');

        if (!hasInternet) {
          _progressController.add(SosProgress.forwarding);
        }
      } catch (e) {
        meshFailed = true;
        meshFailureReason = e.toString();
        developer.log(
          'Mesh origination FAILED (SMS will still be attempted): $meshFailureReason',
          name: 'SosRepository',
          error: e,
        );
      }

      // Block 2 (SMS responsibility): once the backend has ACCEPTED the SOS it
      // notifies the registered contacts itself, exactly once (idempotent
      // ledger). This app only sends its own direct SMS when the backend did
      // not confirm SMS for all of the device's contacts.
      int backendNotifiedContacts = 0;

      if (hasInternet && !meshFailed) {
        try {
          final result = await _backendService
              .uploadPacketResult(emergencyPacket)
              .timeout(const Duration(seconds: 10), onTimeout: () => const IngestResult(UploadOutcome.failed));
          if (result.delivered) {
            _progressController.add(SosProgress.backendConfirmed);
            status = "Delivered";
            backendNotifiedContacts = result.smsContactsNotified;
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

      // SMS: isolated (fixed earlier today) -- a mesh failure above no
      // longer prevents this from running.
      final distinctContacts = phoneNumbers
          .map((p) => p.replaceAll(RegExp(r'\D'), ''))
          .map((d) => d.length > 10 ? d.substring(d.length - 10) : d)
          .toSet()
          .length;
      final backendCoversContacts =
          backendNotifiedContacts > 0 && backendNotifiedContacts >= distinctContacts;

      try {
        if (backendCoversContacts) {
          developer.log(
            'Skipping direct SMS: backend queued SMS for $backendNotifiedContacts contact(s)',
            name: 'SosRepository',
          );
        } else {
          await _smsRepository.sendBulkSMS(
            message: message,
            phoneNumbers: phoneNumbers,
          );
        }
      } catch (e) {
        smsFailed = true;
        smsFailureReason = e.toString().replaceFirst("Exception: ", "");
        developer.log(
          'SMS failed: $smsFailureReason',
          name: 'SosRepository',
        );
      }

      // Public broadcast: also isolated -- a failure here (e.g. if
      // mesh already failed above) shouldn't retroactively mark SMS's
      // success as a total failure either.
      if (alertMode == AlertMode.public) {
        try {
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
        } catch (e) {
          developer.log('Public alert broadcast failed: $e', name: 'SosRepository');
        }
      }

      // Aug 6 2026: overall status now genuinely reflects what
      // actually happened across BOTH channels, not just whichever ran
      // last. If mesh succeeded, the emergency signal genuinely went
      // out regardless of SMS. If mesh failed AND SMS failed, this IS
      // a real total failure -- correctly thrown below so History
      // shows "Failed", not a false "Sent".
      if (meshFailed && smsFailed) {
        throw Exception(
          "Both mesh relay and SMS failed. Mesh: $meshFailureReason SMS: $smsFailureReason",
        );
      }

      if (meshFailed) {
        errorReason = "Mesh relay failed, but SMS was sent to your contacts. "
            "Mesh error: $meshFailureReason";
      } else if (smsFailed) {
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
