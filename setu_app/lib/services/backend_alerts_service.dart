// =====================================================
// SETU Project
// Module : Backend Community Alerts Service
// =====================================================
//
// Talks to the backend's Phase 3 endpoints:
//   GET  /alerts/nearby
//   POST /alerts/{incident_id}/respond
//
// DELIBERATELY SEPARATE FROM features/nearby/ — that existing feature
// (NearbyRepository, NearbyAlertModel, NearbyScreen) shows LOCAL mesh
// AlertPackets, received directly over BLE/Wi-Fi Direct from other
// devices, persisted to SharedPreferences. This is a DIFFERENT data
// source: incidents the BACKEND knows about (whether they arrived via
// mesh relay, direct internet, or voice SOS), fetched by polling with
// this device's own current coordinates. Nothing here is stored
// locally — see docs/MOBILE_BACKEND_CONTRACT.md and the backend's own
// nearby_alert_service.py module docstring on why this is a
// polling-not-push design: no FCM/push infrastructure exists, and the
// backend deliberately does not store user location server-side.
//
// PRIVACY: the backend's /alerts/nearby response is already privacy-safe
// (no reporter identity, no profile data — see the backend's own
// nearby_alert_service.py). This service does no additional filtering;
// it just deserializes exactly what the backend already scoped down.

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;

import 'request_signer.dart';

enum CommunityResponseType {
  nearby,
  canHelp,
  alreadyResponding,
  calledEmergencyServices,
  navigating;

  String get apiValue {
    switch (this) {
      case CommunityResponseType.nearby:
        return 'NEARBY';
      case CommunityResponseType.canHelp:
        return 'CAN_HELP';
      case CommunityResponseType.alreadyResponding:
        return 'ALREADY_RESPONDING';
      case CommunityResponseType.calledEmergencyServices:
        return 'CALLED_EMERGENCY_SERVICES';
      case CommunityResponseType.navigating:
        return 'NAVIGATING';
    }
  }
}

class BackendNearbyAlert {
  final int incidentId;
  final String incidentType;
  final String? senderPriority;
  final double? aiPriority;
  final double distanceKm;
  final DateTime createdAt;
  final String message;

  const BackendNearbyAlert({
    required this.incidentId,
    required this.incidentType,
    required this.distanceKm,
    required this.createdAt,
    required this.message,
    this.senderPriority,
    this.aiPriority,
  });

  factory BackendNearbyAlert.fromJson(Map<String, dynamic> json) {
    return BackendNearbyAlert(
      incidentId: json['incident_id'] as int,
      incidentType: json['incident_type'] as String? ?? 'unknown',
      senderPriority: json['sender_priority'] as String?,
      aiPriority: (json['ai_priority'] as num?)?.toDouble(),
      distanceKm: (json['distance_km'] as num?)?.toDouble() ?? 0.0,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
      message: json['message'] as String? ?? '',
    );
  }
}

class BackendAlertsService {
  BackendAlertsService({
    this.baseUrl = 'https://setu-backend-cy78.onrender.com',
    RequestSigner? signer,
    http.Client? client,
  })  : _signer = signer ?? RequestSigner(),
        _client = client;

  final String baseUrl;
  final RequestSigner _signer;
  final http.Client? _client;

  Future<http.Response> _get(Uri uri, Map<String, String> headers) =>
      _client?.get(uri, headers: headers) ?? http.get(uri, headers: headers);

  Future<http.Response> _post(Uri uri, Map<String, String> headers, List<int> body) =>
      _client?.post(uri, headers: headers, body: body) ?? http.post(uri, headers: headers, body: body);

  /// Fetches OPEN incidents within [radiusKm] of ([latitude], [longitude]).
  /// [senderId] is optional — when given, the backend excludes incidents
  /// this device already responded to (see respond() below).
  ///
  /// Returns an empty list on any failure rather than throwing, so a
  /// polling loop can call this on a timer without wrapping every call
  /// in its own try/catch.
  Future<List<BackendNearbyAlert>> fetchNearby({
    required double latitude,
    required double longitude,
    double radiusKm = 2.0,
    String? senderId,
  }) async {
    try {
      // Block 2: nearby alerts are only served to a registered, signed device.
      // The signature covers the RAW query strings sent below.
      final latStr = latitude.toString();
      final lonStr = longitude.toString();
      final radiusStr = radiusKm.toString();
      final signed = await _signer.headersFor(
        method: 'GET',
        path: '/alerts/nearby',
        parts: [latStr, lonStr, radiusStr],
      );
      final uri = Uri.parse('$baseUrl/alerts/nearby').replace(queryParameters: {
        'lat': latStr,
        'lon': lonStr,
        'radius_km': radiusStr,
        // Must equal the signing key if present; the signer's key is always used.
        if (senderId != null) 'sender_id': signed['X-Setu-Sender']!,
      });

      final response = await _get(uri, signed).timeout(const Duration(seconds: 10));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        developer.log(
          'Nearby alerts fetch rejected: ${response.statusCode} ${response.body}',
          name: 'BackendAlertsService',
        );
        return [];
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(BackendNearbyAlert.fromJson)
          .toList();
    } catch (e) {
      developer.log('Nearby alerts fetch failed: $e', name: 'BackendAlertsService');
      return [];
    }
  }

  /// Records this device's response to [incidentId]. Calling again with
  /// a different [responseType] updates the existing response rather
  /// than creating a duplicate — the backend upserts by
  /// (incident_id, sender_id), see routers/alerts.py.
  ///
  /// Returns true only on a confirmed 2xx from the backend.
  Future<bool> respond({
    required int incidentId,
    required String senderId,
    required CommunityResponseType responseType,
  }) async {
    try {
      final path = '/alerts/$incidentId/respond';
      final bodyBytes = jsonBodyBytes({
        'sender_id': senderId,
        'response_type': responseType.apiValue,
      });
      final signed = await _signer.headersForBody(method: 'POST', path: path, bodyBytes: bodyBytes);
      final response = await _post(
        Uri.parse('$baseUrl$path'),
        {'Content-Type': 'application/json', ...signed},
        bodyBytes,
      ).timeout(const Duration(seconds: 10));

      final ok = response.statusCode >= 200 && response.statusCode < 300;
      developer.log(
        ok
            ? 'Responded to incident $incidentId with ${responseType.apiValue}'
            : 'Response rejected: ${response.statusCode} ${response.body}',
        name: 'BackendAlertsService',
      );
      return ok;
    } catch (e) {
      developer.log('Respond failed: $e', name: 'BackendAlertsService');
      return false;
    }
  }
}
