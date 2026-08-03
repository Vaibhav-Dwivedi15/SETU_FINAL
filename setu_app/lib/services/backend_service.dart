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
  /// backend, feeding ResponderRegistry.syncFromBackend(). This is what
  /// closes the termination-authorization gap: until this successfully
  /// returns at least once, ResponderRegistry stays empty and termination
  /// packets are accepted with only a logged warning (fail-open, by
  /// design, documented in responder_registry.dart).
  ///
  /// Deliberately unauthenticated — no API key required. The contents are
  /// public keys, which are meant to be public; every relay device needs
  /// this list to verify a termination packet's signer, not just the
  /// backend or a logged-in responder. This mirrors /ingest being open
  /// while /incidents (which shows real incident content) stays gated.
  ///
  /// Returns null on ANY failure (network, non-2xx, unexpected shape) —
  /// never an empty list on failure — so the caller can skip this sync
  /// cycle rather than wipe out a previously-synced registry with nothing.
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
}