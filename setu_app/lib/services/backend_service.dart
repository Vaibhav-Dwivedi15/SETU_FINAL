import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'package:http/http.dart' as http;
import '../mesh/models/mesh_packet.dart';
import 'request_signer.dart';
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

/// Outcome of one upload plus what the backend reported about SMS (Block 2).
class IngestResult {
  const IngestResult(this.outcome, {this.smsContactsNotified = 0});

  final UploadOutcome outcome;

  /// Number of emergency contacts the BACKEND has queued SMS for (idempotent
  /// ledger). The app only sends its own direct SMS when this does not cover
  /// all of the device's contacts -- see SosRepository.
  final int smsContactsNotified;

  bool get delivered =>
      outcome == UploadOutcome.accepted || outcome == UploadOutcome.duplicate;
}

class BackendService {
  BackendService({
    this.baseUrl = 'https://setu-backend-cy78.onrender.com',
    http.Client? client,
    RequestSigner? signer,
  })  : _client = client,
        _signer = signer ?? RequestSigner();

  final String baseUrl;
  final http.Client? _client;
  final RequestSigner _signer;

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
  Future<UploadOutcome> uploadPacketDetailed(MeshPacket packet) async =>
      (await uploadPacketResult(packet)).outcome;

  Future<IngestResult> uploadPacketResult(MeshPacket packet) async {
    try {
      final response = await _post(
        Uri.parse('$baseUrl/ingest'),
        {'Content-Type': 'application/json'},
        jsonEncode({
          'packets': [packet.toJson()],
        }),
      ).timeout(const Duration(seconds: 10));

      // HTTP status only says the request was processed (or throttled/broken);
      // per-packet acceptance is in the body. 429/5xx/anything non-2xx => the
      // packet stays queued and is retried.
      if (response.statusCode < 200 || response.statusCode >= 300) {
        developer.log('Upload failed: HTTP ${response.statusCode}', name: 'BackendService');
        return const IngestResult(UploadOutcome.failed);
      }
      final outcome = classifyIngestResponse(response.body, packet.packetId);
      developer.log('Upload ${packet.packetId}: ${outcome.name}', name: 'BackendService');
      return IngestResult(outcome, smsContactsNotified: _smsNotified(response.body, packet.packetId));
    } catch (e) {
      developer.log('Upload failed: $e', name: 'BackendService');
      return const IngestResult(UploadOutcome.failed);
    }
  }

  static int _smsNotified(String body, String packetId) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) return 0;
      for (final list in ['accepted', 'duplicates']) {
        final entries = decoded[list];
        if (entries is! List) continue;
        for (final entry in entries) {
          if (entry is Map && entry['packet_id'] == packetId) {
            final n = entry['sms_contacts_notified'];
            return n is int && n > 0 ? n : 0;
          }
        }
      }
    } catch (_) {}
    return 0;
  }

  /// Interprets one /ingest batch response for [packetId] (Block 2 contract,
  /// docs/backend/PACKET_CONTRACT.md). The backend reports each packet in
  /// exactly one of `accepted` / `duplicates` / `rejected` / `failed`; every
  /// entry carries `packet_id` and `status`. Anything unrecognised, missing or
  /// self-contradictory is [UploadOutcome.failed] (retry) -- never a delivery.
  static UploadOutcome classifyIngestResponse(String body, String packetId) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) return UploadOutcome.failed;
      final accepted = decoded['accepted'];
      final rejected = decoded['rejected'];
      if (accepted is! List || rejected is! List) return UploadOutcome.failed;
      // Absent on a pre-Block-2 backend, where duplicates came back inside `rejected`.
      final duplicates = decoded['duplicates'] is List ? decoded['duplicates'] as List : const [];
      final failedList = decoded['failed'] is List ? decoded['failed'] as List : const [];

      UploadOutcome? outcome;
      void consider(List entries, UploadOutcome listOutcome, String status) {
        for (final entry in entries) {
          if (entry is! Map || entry['packet_id'] != packetId) continue;
          final declared = entry['status'];
          // A status that contradicts the list it is in is corrupt: fail safe.
          if (declared != null && declared != status) {
            outcome = UploadOutcome.failed;
            return;
          }
          // Legacy backend (no `status`): duplicates were `rejected` with this reason prefix.
          final legacyDuplicate = declared == null &&
              listOutcome == UploadOutcome.rejected &&
              entry['reason'] is String &&
              (entry['reason'] as String).startsWith('duplicate packet_id');
          final next = legacyDuplicate ? UploadOutcome.duplicate : listOutcome;
          // The same packet_id in two lists is contradictory: fail safe.
          if (outcome != null && outcome != next) {
            outcome = UploadOutcome.failed;
          } else {
            outcome = next;
          }
        }
      }

      consider(accepted, UploadOutcome.accepted, 'ACCEPTED');
      consider(duplicates, UploadOutcome.duplicate, 'DUPLICATE');
      consider(rejected, UploadOutcome.rejected, 'REJECTED');
      consider(failedList, UploadOutcome.failed, 'FAILED');
      return outcome ?? UploadOutcome.failed;
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
      // Block 2: proof of possession -- the request is signed with this device's
      // Ed25519 key (the same key whose public half IS senderId).
      final bodyBytes = jsonBodyBytes({
        'sender_id': senderId,
        'name': name,
        'age': age,
        'gender': gender,
        'medical_history': medicalHistory,
        'emergency_contacts': emergencyContacts,
      });
      final signed = await _signer.headersForBody(method: 'POST', path: '/register', bodyBytes: bodyBytes);
      if (signed['X-Setu-Sender'] != senderId) {
        developer.log('Registration skipped: senderId is not this device key', name: 'BackendService');
        return false;
      }
      final response = await http
          .post(
            Uri.parse('$baseUrl/register'),
            headers: {'Content-Type': 'application/json', ...signed},
            body: bodyBytes,
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
