import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'package:http/http.dart' as http;
import '../mesh/models/mesh_packet.dart';
/// Block 1: what the backend actually did with an uploaded packet.
enum UploadOutcome {
  /// Backend listed the packet_id under `accepted`.
  accepted,

  /// Backend already holds this packet_id (`duplicate packet_id ...`):
  /// it reached the backend, so it counts as delivered.
  duplicate,

  /// Backend answered but refused it (bad signature, expired, schema,
  /// unauthorized). Retrying the same bytes cannot succeed.
  rejected,

  /// No usable answer: offline, timeout, non-2xx, or a 2xx body that is
  /// not the /ingest contract (e.g. a captive portal). Worth retrying.
  failed,
}

class BackendService {
  BackendService({
    this.baseUrl = 'https://setu-backend-cy78.onrender.com',
    http.Client? client,
  }) : _client = client;

  final String baseUrl;
  final http.Client? _client;

  Future<http.Response> _post(Uri uri, Map<String, String> headers, String body) {
    final client = _client;
    return client == null
        ? http.post(uri, headers: headers, body: body)
        : client.post(uri, headers: headers, body: body);
  }
  Future<bool> hasRealInternet() async {
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 3));
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } on SocketException {
      return false;
    } on TimeoutException {
      return false;
    }
  }
  /// Aug 6 2026 fix: /ingest expects {"packets": [...]} -- an array
  /// wrapper, for batching -- but this was POSTing the bare packet
  /// object directly as the body. Confirmed root cause of every
  /// recurring 422 Ayush found in his debug logging: every packet was
  /// otherwise well-formed (real signature, correct fields), just
  /// missing the envelope. Fixed by wrapping in "packets": [packet].
  /// Sending a single-element array (not batching multiple packets
  /// per call) -- this device only ever has one packet to upload at a
  /// time via this path; true batching would be a separate change to
  /// the local queue's retry logic, not done here.
  /// True only if the packet is now known to the backend (accepted, or
  /// already stored). Kept for existing callers; see [uploadPacketDetailed].
  Future<bool> uploadPacket(MeshPacket packet) async {
    final outcome = await uploadPacketDetailed(packet);
    return outcome == UploadOutcome.accepted || outcome == UploadOutcome.duplicate;
  }

  /// Block 1: /ingest answers HTTP 200 with `{accepted: [...], rejected:
  /// [...]}` even when it refuses the packet, so a bare 2xx check treated
  /// a REJECTED packet as delivered -- marking it uploaded and
  /// originating an ACK for something the backend threw away. The
  /// per-packet result is now read from the body.
  ///
  /// (Backend follow-up for BLOCK 2: a rejected-then-resent packet_id is
  /// reported as "duplicate packet_id", so a forged copy that reached the
  /// backend first would make the genuine one look delivered. That needs
  /// a backend change and is documented, not worked around, here.)
  Future<UploadOutcome> uploadPacketDetailed(MeshPacket packet) async {
    try {
      final response = await _post(
        Uri.parse('$baseUrl/ingest'),
        {'Content-Type': 'application/json'},
        jsonEncode({
          'packets': [packet.toJson()],
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        developer.log('Upload failed: HTTP ${response.statusCode}', name: 'BackendService');
        return UploadOutcome.failed;
      }
      final outcome = classifyIngestResponse(response.body, packet.packetId);
      developer.log('Upload ${packet.packetId}: ${outcome.name}', name: 'BackendService');
      return outcome;
    } catch (e) {
      developer.log('Upload failed: $e', name: 'BackendService');
      return UploadOutcome.failed;
    }
  }

  /// Pure parsing of an /ingest 2xx body for one packet id.
  static UploadOutcome classifyIngestResponse(String body, String packetId) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) return UploadOutcome.failed;
      final accepted = decoded['accepted'];
      final rejected = decoded['rejected'];
      if (accepted is! List || rejected is! List) return UploadOutcome.failed;

      for (final entry in accepted) {
        if (entry is Map && entry['packet_id'] == packetId) return UploadOutcome.accepted;
      }
      for (final entry in rejected) {
        if (entry is Map && entry['packet_id'] == packetId) {
          final reason = entry['reason'];
          if (reason is String && reason.startsWith('duplicate packet_id')) {
            return UploadOutcome.duplicate;
          }
          return UploadOutcome.rejected;
        }
      }
      // Answered, but our packet is in neither list.
      return UploadOutcome.failed;
    } catch (_) {
      return UploadOutcome.failed;
    }
  }

  Future<List<String>?> fetchResponderKeys() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/responders/keys'))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        developer.log(
          'Responder registry fetch rejected: ${response.statusCode}',
          name: 'BackendService',
        );
        return null;
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic> ||
          decoded['responder_public_keys'] is! List) {
        developer.log(
          'Responder registry fetch: unexpected response shape',
          name: 'BackendService',
        );
        return null;
      }
      return List<String>.from(decoded['responder_public_keys'] as List);
    } catch (e) {
      developer.log('Responder registry fetch failed: $e', name: 'BackendService');
      return null;
    }
  }

  Future<bool> registerProfile({
    required String senderId,
    required String name,
    int? age,
    String? gender,
    String? medicalHistory,
    required List<String> emergencyContacts,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/register'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'sender_id': senderId,
              'name': name,
              'age': age,
              'gender': gender,
              'medical_history': medicalHistory,
              'emergency_contacts': emergencyContacts,
            }),
          )
          .timeout(const Duration(seconds: 10));
      final ok = response.statusCode >= 200 && response.statusCode < 300;
      developer.log(
        ok ? 'Profile registered/updated for $senderId' : 'Registration rejected: ${response.statusCode} ${response.body}',
        name: 'BackendService',
      );
      return ok;
    } catch (e) {
      developer.log('Registration failed: $e', name: 'BackendService');
      return false;
    }
  }
}
