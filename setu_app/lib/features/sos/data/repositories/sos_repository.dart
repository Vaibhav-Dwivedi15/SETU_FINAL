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

class SosRepository {
  final ContactRepository _contactRepository = ContactRepository();
  final LocationService _locationService = LocationService();
  final SmsRepository _smsRepository = SmsRepository();
  final HistoryRepository _historyRepository = HistoryRepository();
  final NearbyRepository _nearbyRepository = NearbyRepository();
  final MeshPermissionService _permissionService = const MeshPermissionService();
  final EmergencyPacketBuilder _emergencyPacketBuilder = EmergencyPacketBuilder();
  final AlertPacketBuilder _alertPacketBuilder = AlertPacketBuilder();

  static const MethodChannel _meshChannel = MethodChannel('com.setu.mesh/methods');

  Future<void> triggerSOS({
    required AlertMode alertMode,
    EmergencyCategory category = EmergencyCategory.generalSos,
  }) async {
    // Added Aug 4 2026: the permission gate at login covers the normal
    // path, but permissions can be revoked later from OS settings at
    // any time -- an SOS is the one moment this app cannot afford to
    // silently fail because a radio permission got turned off since
    // login. Re-check and re-request right here, every time, before
    // doing anything else. If the user permanently denied something,
    // requestAll() can't fix that (only openAppSettings() can) -- in
    // that case this still throws below so the caller's UI can prompt
    // them to open settings, instead of the SOS silently going nowhere.
    if (!await _permissionService.hasAll()) {
      final stillMissing = await _permissionService.requestAll();
      if (stillMissing.isNotEmpty) {
        throw Exception(
          "SETU needs Bluetooth, Wi-Fi and location permissions to relay "
          "your SOS without internet. Please allow them and try again.",
        );
      }
    }

    // Load Emergency Contacts
    final contacts = await _contactRepository.getContacts();

    if (contacts.isEmpty) {
      throw Exception(
        "No emergency contacts found. Please add at least one contact.",
      );
    }

    // Current Location
    final location = await _locationService.getCurrentLocation();

    // Extract Phone Numbers
    final phoneNumbers = contacts.map((e) => e.phone).toList();

    // Google Maps Link
    final mapsLink =
        "https://maps.google.com/?q=${location.latitude},${location.longitude}";

    // Mode Name
    final modeName = alertMode == AlertMode.private
        ? "PRIVATE SOS"
        : "PUBLIC SOS";

    // SOS Message — now customized per emergency category
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
    // NOT renamed, deliberately (Aug 4 2026 gap analysis): "Delivered"
    // here really means "handed to the mesh/SMS layer", not "confirmed
    // reaching the backend" -- see AckPacket for the real confirmation
    // mechanism. Left as "Delivered" because
    // history_screen.dart's _isSuccessStatus() does an exact string
    // match on "delivered" for its green/success styling -- renaming
    // this without also updating that check would silently break the
    // history screen's success indicator. Fixing the overclaim properly
    // means wiring MeshService.acknowledgments into HistoryRepository
    // (update-by-emergencyId once a real ack arrives) and updating
    // _isSuccessStatus() together, in one change -- not done here to
    // avoid a half-finished, UI-breaking rename.
    String status = "Delivered";
    String errorReason = "";

    try {
      // Added Aug 4 2026 -- THE critical missing piece found in the gap
      // analysis: until this line existed, triggerSOS() never actually
      // used the mesh layer at all, despite it being fully built and
      // tested. SMS alone needs cell signal, which is exactly the case
      // this app exists for NOT having. This is what makes an SOS
      // actually reach a mesh of nearby phones with zero signal.
      //
      // Runs regardless of alertMode (private vs public only changes
      // whether a community AlertPacket ALSO goes out below) -- every
      // SOS, private or public, must go over the mesh.
      final emergencyPacket = await _emergencyPacketBuilder.buildEmergencyPacket(
        latitude: location.latitude,
        longitude: location.longitude,
        message: message,
        category: category,
      );
      await MeshLocator.instance.meshService.originate(emergencyPacket);

      // Feeds this device's just-fetched GPS reading to the native
      // relay engine (see PacketRelayEngine.kt's location-aware
      // re-entry) -- best-effort, never blocks or fails the SOS itself
      // if the channel call errors for any reason.
      try {
        await _meshChannel.invokeMethod('updateLocation', {
          'latitude': location.latitude,
          'longitude': location.longitude,
        });
      } catch (_) {
        // Non-fatal -- relay dedup just falls back to packet-id-only
        // behavior for this device until the next successful update.
      }

      await _smsRepository.sendBulkSMS(
        message: message,
        phoneNumbers: phoneNumbers,
      );
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

        // Real community broadcast over the mesh (was previously just
        // the local-only NearbyRepository entry above, which nothing
        // else on the mesh could ever see). No sender identity or
        // contact info in this packet -- see alert_packet.dart's
        // privacy note.
        final alertPacket = await _alertPacketBuilder.buildAlertPacket(
          incidentType: category.name,
          latitude: location.latitude,
          longitude: location.longitude,
        );
        await MeshLocator.instance.meshService.originate(alertPacket);
      }
      // Government backend notification happens automatically once
      // this packet (or a relayed copy of it) reaches any device with
      // real internet -- see MeshServiceImpl._tryUpload. Nothing further
      // needed here.
    } catch (e) {
      status = "Failed";
      retryCount = 3;
      errorReason = e.toString();

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
        ),
      );
    }
  }
}
