import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'package:http/http.dart' as http;
import '../mesh/models/mesh_packet.dart';
class BackendService {
  BackendService({this.baseUrl = 'https://setu-backend-cy78.onrender.com'});
  final String baseUrl;
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
  Future<bool> uploadPacket(MeshPacket packet) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/ingest'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'packets': [packet.toJson()],
            }),
          )
          .timeout(const Duration(seconds: 10));
      final ok = response.statusCode >= 200 && response.statusCode < 300;
      developer.log(
        ok ? 'Uploaded packet ${packet.packetId}' : 'Upload rejected: ${response.statusCode} ${response.body}',
        name: 'BackendService',
      );
      return ok;
    } catch (e) {
      developer.log('Upload failed: $e', name: 'BackendService');
      return false;
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
