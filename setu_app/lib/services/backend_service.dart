import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'package:http/http.dart' as http;
import '../mesh/models/mesh_packet.dart';
/// Handles the "exit node" step of the pipeline (Doc 2, Steps 9-10): once
/// a device has real internet, silently upload any packet it's carrying to
/// the backend. No UI prompt, no user action — this is what makes a
/// bystander's phone a true silent carrier, not just a display for logs.
class BackendService {
  BackendService({this.baseUrl = 'https://setu-backend-cy78.onrender.com'});
  final String baseUrl;
  /// A real reachability check, not just "is Wi-Fi/data connected." A
  /// phone can show as connected while only linked to another mesh device
  /// over Wi-Fi Direct, which is not real internet — this catches that.
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
  /// Returns true on a successful upload, false otherwise. Does not retry
  /// or persist on failure — that's the SQLite store-and-forward queue,
  /// intentionally a separate, later piece of work.
  Future<bool> uploadPacket(MeshPacket packet) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/ingest'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(packet.toJson()),
          )
          .timeout(const Duration(seconds: 10));
      final ok = response.statusCode >= 200 && response.statusCode < 300;
      developer.log(
        ok ? 'Uploaded packet ${packet.packetId}' : 'Upload rejected: ${response.statusCode}',
        name: 'BackendService',
      );
      return ok;
    } catch (e) {
      developer.log('Upload failed: $e', name: 'BackendService');
      return false;
    }
  }
  /// Fetches the current list of trusted responder public keys from the
  /// backend, feeding ResponderRegistry.syncFromBackend().
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

  /// Added Aug 6 2026: registers/updates this device's profile with the
  /// backend over normal internet -- this is what makes the backend's
  /// existing notify_emergency_contacts() (server-side SMS Gateway, live
  /// since Aug 2) actually able to find contacts for a given sender_id.
  /// Without this call ever happening, UserProfile lookup in
  /// incident_service.handle_sos_packet() always returns nothing, and
  /// the backend-side SMS notification silently never fires -- this was
  /// the real, previously-undiscovered gap: the SMS Gateway mechanism
  /// was fully built and working, just never fed any data.
  ///
  /// POST /register now upserts (see register.py) -- safe to call this
  /// every time the local profile or contact list changes, not just
  /// once. Returns true only on a genuine 2xx from the backend; false
  /// on any failure (offline, timeout, server error) -- callers should
  /// treat this as best-effort and never block the user's flow on it.
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
