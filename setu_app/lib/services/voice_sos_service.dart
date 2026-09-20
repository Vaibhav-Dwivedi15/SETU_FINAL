// =====================================================
// SETU Project
// Module : Voice SOS Service
// =====================================================
//
// Uploads a recorded audio file to the backend's POST /ingest/voice,
// which transcribes it (Whisper, translate mode) and runs the result
// through the full emergency pipeline. See docs/MOBILE_BACKEND_CONTRACT.md.
//
// WHY THIS IS A SEPARATE PATH FROM THE MESH SOS FLOW: audio is far too
// large to relay hop-by-hop over BLE/Wi-Fi Direct, which is the whole
// constraint the mesh path is built around. This requires a direct
// internet connection to the backend — it does NOT work offline, and is
// NOT a mesh-relayed report. checkAvailability() should be called before
// showing a record button, so a user without connectivity doesn't record
// something that can't be sent.
//
// TRUST LEVEL — IMPORTANT: voice uploads are NOT Ed25519-signed (there is
// no signature scheme over audio in the frozen packet spec). The backend
// marks these reports as arriving unsigned in the incident's audit
// trail. Do not present voice SOS in the UI as carrying the same
// cryptographic guarantee as a mesh-relayed, signed report.
//
// MULTILINGUAL — WHAT'S REAL: Whisper runs in translate mode, so a user
// can speak Hindi, Bengali, Tamil, etc. and the backend understands it.
// The STORED message is the English translation — the original wording
// is not kept. Don't claim the app "remembers the message in your own
// language"; it doesn't, by the AI team's own deliberate design choice.

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:http/http.dart' as http;

class VoiceSosAvailability {
  final bool available;
  final String detail;

  const VoiceSosAvailability({required this.available, required this.detail});
}

class VoiceSosResult {
  final bool success;
  final String detail;
  final String? transcript;
  final int? incidentId;

  const VoiceSosResult({
    required this.success,
    required this.detail,
    this.transcript,
    this.incidentId,
  });
}

class VoiceSosService {
  VoiceSosService({this.baseUrl = 'https://setu-backend-cy78.onrender.com'});

  final String baseUrl;

  /// Checks whether the backend can actually process voice right now
  /// (Whisper + ffmpeg installed server-side). Call this before showing
  /// a record button — the server-side dependency is heavy and may not
  /// be provisioned on every deployment.
  Future<VoiceSosAvailability> checkAvailability() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/ingest/voice/status'))
          .timeout(const Duration(seconds: 8));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return const VoiceSosAvailability(
          available: false,
          detail: 'Voice SOS status check failed.',
        );
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      return VoiceSosAvailability(
        available: decoded['available'] as bool? ?? false,
        detail: decoded['detail'] as String? ?? '',
      );
    } catch (e) {
      developer.log('Voice SOS availability check failed: $e', name: 'VoiceSosService');
      return const VoiceSosAvailability(
        available: false,
        detail: 'Could not reach the server to check voice SOS availability.',
      );
    }
  }

  /// Uploads [audioFile] as a voice SOS. [senderId] is this device's
  /// hex Ed25519 public key (same identity used for signed mesh
  /// packets, even though this particular upload isn't itself signed).
  ///
  /// Returns success=false with a user-facing [VoiceSosResult.detail]
  /// on any failure — never throws, mirrors the rest of this project's
  /// "a UI always has something sensible to show" convention.
  Future<VoiceSosResult> uploadVoiceSos({
    required File audioFile,
    required String senderId,
    double latitude = 0.0,
    double longitude = 0.0,
    String? priority,
  }) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/ingest/voice'),
      );
      request.fields['sender_id'] = senderId;
      request.fields['latitude'] = latitude.toString();
      request.fields['longitude'] = longitude.toString();
      if (priority != null) request.fields['priority'] = priority;
      request.files.add(await http.MultipartFile.fromPath('file', audioFile.path));

      final streamedResponse = await request.send().timeout(const Duration(seconds: 60));
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final detail = _extractDetail(response.body) ??
            'Voice SOS upload failed (server error ${response.statusCode}).';
        developer.log(
          'Voice SOS upload rejected: ${response.statusCode} $detail',
          name: 'VoiceSosService',
        );
        return VoiceSosResult(success: false, detail: detail);
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      return VoiceSosResult(
        success: true,
        detail: decoded['note'] as String? ?? 'Voice SOS sent.',
        transcript: decoded['transcript'] as String?,
        incidentId: decoded['incident_id'] as int?,
      );
    } catch (e) {
      developer.log('Voice SOS upload failed: $e', name: 'VoiceSosService');
      return const VoiceSosResult(
        success: false,
        detail: 'Could not reach the server. Voice SOS needs an internet connection '
            '(it cannot travel through the offline mesh — audio is too large to relay).',
      );
    }
  }

  String? _extractDetail(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic> && decoded['detail'] is String) {
        return decoded['detail'] as String;
      }
    } catch (_) {
      // Not JSON.
    }
    return null;
  }
}
