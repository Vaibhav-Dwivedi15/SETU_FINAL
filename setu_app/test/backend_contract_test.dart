import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:setu_app/mesh/enums/emergency_priority.dart';
import 'package:setu_app/mesh/models/emergency_packet.dart';
import 'package:setu_app/mesh/services/signing_service.dart';
import 'package:setu_app/services/backend_alerts_service.dart';
import 'package:setu_app/services/backend_service.dart';
import 'package:setu_app/services/request_signer.dart';

/// BLOCK 2 -- mobile side of the backend contract:
///  * /ingest per-packet states (ACCEPTED / DUPLICATE / REJECTED / FAILED)
///  * signed requests (register / nearby / respond / voice) reproduce the
///    backend's canonical string and Ed25519 signatures byte for byte, from the
///    shared vector file docs/backend/contract/request_signing_vectors.json
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final vectors = jsonDecode(File('../docs/backend/contract/request_signing_vectors.json').readAsStringSync())
      as Map<String, dynamic>;
  final store = <String, String>{'setu_signing_private_key_seed': vectors['seed_hex'] as String};

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'read':
          return store[call.arguments['key']];
        case 'write':
          store[call.arguments['key'] as String] = call.arguments['value'] as String;
          return null;
        case 'containsKey':
          return store.containsKey(call.arguments['key']);
        default:
          return null;
      }
    });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  EmergencyPacket sos() => EmergencyPacket(
        packetId: 'sos-1',
        senderId: 'sender',
        timestamp: DateTime.now().toUtc(),
        nonce: 'nonce-1',
        ttl: 5,
        hopCount: 0,
        signature: 'sig',
        emergencyId: 'sos-1',
        latitude: 1.0,
        longitude: 2.0,
        message: 'help',
        priority: EmergencyPriority.high,
      );

  group('/ingest per-packet states', () {
    String body({List accepted = const [], List duplicates = const [], List rejected = const [], List failed = const []}) =>
        jsonEncode({'accepted': accepted, 'duplicates': duplicates, 'rejected': rejected, 'failed': failed});
    UploadOutcome classify(String b) => BackendService.classifyIngestResponse(b, 'p');

    test('each state maps to exactly one outcome', () {
      expect(classify(body(accepted: [{'packet_id': 'p', 'status': 'ACCEPTED'}])), UploadOutcome.accepted);
      expect(classify(body(duplicates: [{'packet_id': 'p', 'status': 'DUPLICATE'}])), UploadOutcome.duplicate);
      expect(classify(body(rejected: [{'packet_id': 'p', 'status': 'REJECTED', 'code': 'invalid_signature'}])),
          UploadOutcome.rejected);
      expect(classify(body(failed: [{'packet_id': 'p', 'status': 'FAILED', 'retryable': true}])), UploadOutcome.failed);
    });

    test('rejected reasons are never deliveries, including packet_id_conflict', () {
      for (final code in [
        'invalid_signature', 'stale', 'future_timestamp', 'invalid_ttl', 'schema', 'too_large',
        'unknown_type', 'unsupported_type', 'unauthorized_responder', 'packet_id_conflict', 'malformed',
      ]) {
        expect(classify(body(rejected: [{'packet_id': 'p', 'status': 'REJECTED', 'code': code, 'reason': 'x'}])),
            UploadOutcome.rejected, reason: code);
      }
    });

    test('other packets in the batch do not affect this packet', () {
      final b = body(
        accepted: [{'packet_id': 'q', 'status': 'ACCEPTED'}],
        rejected: [{'packet_id': 'p', 'status': 'REJECTED'}],
      );
      expect(classify(b), UploadOutcome.rejected);
    });

    test('contradictions and unknowns fail safe (retry, never delivered)', () {
      // status disagrees with the list it is in
      expect(classify(body(accepted: [{'packet_id': 'p', 'status': 'REJECTED'}])), UploadOutcome.failed);
      // same packet reported in two lists
      expect(classify(body(
        accepted: [{'packet_id': 'p', 'status': 'ACCEPTED'}],
        rejected: [{'packet_id': 'p', 'status': 'REJECTED'}],
      )), UploadOutcome.failed);
      expect(classify(body()), UploadOutcome.failed);
      expect(classify('<html>captive portal</html>'), UploadOutcome.failed);
      expect(classify('{"accepted": 1}'), UploadOutcome.failed);
      expect(classify('{"accepted": [], "rejected": [{"packet_id": 7}]}'), UploadOutcome.failed);
    });

    test('legacy backend (no status, duplicate inside rejected) still reads as duplicate', () {
      expect(classify(body(rejected: [{'packet_id': 'p', 'reason': 'duplicate packet_id'}])), UploadOutcome.duplicate);
      expect(classify(body(rejected: [{'packet_id': 'p', 'reason': 'invalid signature'}])), UploadOutcome.rejected);
    });

    test('HTTP layer: non-2xx and transport errors are failed, 200 with rejection is not delivery', () async {
      Future<IngestResult> run(http.Response Function(http.Request) h) => BackendService(
            baseUrl: 'https://x.test',
            client: http_testing.MockClient((r) async => h(r)),
          ).uploadPacketResult(sos());

      expect((await run((_) => http.Response('', 429))).outcome, UploadOutcome.failed);
      expect((await run((_) => http.Response('boom', 500))).outcome, UploadOutcome.failed);
      expect((await run((_) => http.Response('', 413))).outcome, UploadOutcome.failed);
      final rejected = await run((_) => http.Response(
          body(rejected: [{'packet_id': 'sos-1', 'status': 'REJECTED', 'code': 'stale'}]), 200));
      expect(rejected.outcome, UploadOutcome.rejected);
      expect(rejected.delivered, isFalse);
    });

    test('duplicate counts as delivered (backend already holds the identical packet)', () async {
      final r = await BackendService(
        baseUrl: 'https://x.test',
        client: http_testing.MockClient((_) async => http.Response(
            body(duplicates: [{'packet_id': 'sos-1', 'status': 'DUPLICATE', 'sms_contacts_notified': 2}]), 200)),
      ).uploadPacketResult(sos());
      expect(r.outcome, UploadOutcome.duplicate);
      expect(r.delivered, isTrue);
      expect(r.smsContactsNotified, 2);
    });

    test('sms_contacts_notified is read only from this packet\'s own accepted/duplicate entry', () async {
      Future<int> sms(String b) async => (await BackendService(
            baseUrl: 'https://x.test',
            client: http_testing.MockClient((_) async => http.Response(b, 200)),
          ).uploadPacketResult(sos()))
              .smsContactsNotified;

      expect(await sms(body(accepted: [{'packet_id': 'sos-1', 'status': 'ACCEPTED', 'sms_contacts_notified': 3}])), 3);
      expect(await sms(body(accepted: [{'packet_id': 'other', 'status': 'ACCEPTED', 'sms_contacts_notified': 3}])), 0);
      expect(await sms(body(rejected: [{'packet_id': 'sos-1', 'status': 'REJECTED', 'sms_contacts_notified': 3}])), 0);
      expect(await sms(body(accepted: [{'packet_id': 'sos-1', 'status': 'ACCEPTED', 'sms_contacts_notified': 'x'}])), 0);
    });
  });

  group('REAL backend responses (docs/backend/contract/ingest_scenarios.json)', () {
    // Recorded by Backend/tests/test_e2e_contract.py from the real /ingest pipeline.
    final scenarios = (jsonDecode(File('../docs/backend/contract/ingest_scenarios.json').readAsStringSync()) as List)
        .cast<Map<String, dynamic>>();

    test('scenario file is non-trivial and covers every backend state', () {
      expect(scenarios.length, greaterThan(15));
      expect(scenarios.map((s) => s['backend_state']).toSet(), containsAll(['ACCEPTED', 'DUPLICATE', 'REJECTED']));
    });

    for (final s in scenarios) {
      test('${s['scenario']}: backend ${s['backend_state']} == mobile ${s['mobile_outcome']}', () {
        final outcome = BackendService.classifyIngestResponse(s['response_body'] as String, s['packet_id'] as String);
        expect(outcome.name, s['mobile_outcome'], reason: 'mobile must read the backend state it was given');
        final delivered = outcome == UploadOutcome.accepted || outcome == UploadOutcome.duplicate;
        expect(delivered, s['mobile_acks'], reason: 'ACK iff the backend holds the packet');
      });
    }
  });

  group('signed requests (shared cross-language vectors)', () {
    final cases = (vectors['cases'] as List).cast<Map<String, dynamic>>();

    test('sender id derived from the seed matches the vector', () async {
      expect(await RequestSigner().senderId(), vectors['sender_id']);
    });

    for (final c in ['register', 'respond', 'nearby', 'voice']) {
      test('$c: canonical string and Ed25519 signature are byte-identical to the backend', () async {
        final v = cases.firstWhere((x) => x['name'] == c);
        final signer = RequestSigner();
        final parts = <String>[];
        if (c == 'register' || c == 'respond') {
          parts.add(await RequestSigner.sha256Hex(utf8.encode(v['body_utf8'] as String)));
        } else if (c == 'nearby') {
          parts.addAll(['28.6139', '77.209', '2.0']);
        } else {
          final audio = _hex(v['audio_bytes_hex'] as String);
          parts.addAll([await RequestSigner.sha256Hex(audio), '28.6139', '77.209', 'high', '']);
        }
        expect(parts, (v['parts'] as List).cast<String>());

        final headers = await signer.headersFor(
          method: v['method'] as String,
          path: v['path'] as String,
          parts: parts,
          timestamp: vectors['timestamp'] as String,
          nonce: vectors['nonce'] as String,
        );
        expect(
          RequestSigner.canonicalString(
            method: v['method'] as String,
            path: v['path'] as String,
            senderId: vectors['sender_id'] as String,
            timestamp: vectors['timestamp'] as String,
            nonce: vectors['nonce'] as String,
            parts: parts,
          ),
          v['canonical'],
        );
        expect(headers['X-Setu-Signature'], v['signature']);
        expect(headers['X-Setu-Sender'], vectors['sender_id']);
      });
    }

    test('default headers are fresh, well-formed and use a new nonce every time', () async {
      final signer = RequestSigner();
      final a = await signer.headersFor(method: 'GET', path: '/alerts/nearby', parts: ['1', '2', '3']);
      final b = await signer.headersFor(method: 'GET', path: '/alerts/nearby', parts: ['1', '2', '3']);
      expect(a['X-Setu-Nonce'], isNot(b['X-Setu-Nonce']));
      expect(RegExp(r'^[A-Za-z0-9_-]{16,128}$').hasMatch(a['X-Setu-Nonce']!), isTrue);
      expect(RegExp(r'^[0-9a-f]{128}$').hasMatch(a['X-Setu-Signature']!), isTrue);
      expect(RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,9})?Z$').hasMatch(a['X-Setu-Timestamp']!), isTrue);
      final ts = DateTime.parse(a['X-Setu-Timestamp']!);
      expect(DateTime.now().toUtc().difference(ts).abs().inSeconds, lessThan(5));
    });

    test('nearby request carries signed raw query strings and verifies', () async {
      late http.Request seen;
      final service = BackendAlertsService(
        baseUrl: 'https://x.test',
        client: http_testing.MockClient((r) async {
          seen = r;
          return http.Response('[]', 200);
        }),
      );
      await service.fetchNearby(latitude: 28.6139, longitude: 77.209, radiusKm: 2.0);
      final h = seen.headers;
      final canonical = RequestSigner.canonicalString(
        method: 'GET',
        path: '/alerts/nearby',
        senderId: h['X-Setu-Sender']!,
        timestamp: h['X-Setu-Timestamp']!,
        nonce: h['X-Setu-Nonce']!,
        parts: [seen.url.queryParameters['lat']!, seen.url.queryParameters['lon']!, seen.url.queryParameters['radius_km']!],
      );
      expect(await SigningService().verify(canonical, h['X-Setu-Sender']!, h['X-Setu-Signature']!), isTrue);
    });

    test('respond request signs the exact body bytes sent', () async {
      late http.Request seen;
      final service = BackendAlertsService(
        baseUrl: 'https://x.test',
        client: http_testing.MockClient((r) async {
          seen = r;
          return http.Response('{}', 200);
        }),
      );
      final sender = await RequestSigner().senderId();
      expect(await service.respond(incidentId: 7, senderId: sender, responseType: CommunityResponseType.canHelp), isTrue);
      final h = seen.headers;
      final canonical = RequestSigner.canonicalString(
        method: 'POST',
        path: '/alerts/7/respond',
        senderId: h['X-Setu-Sender']!,
        timestamp: h['X-Setu-Timestamp']!,
        nonce: h['X-Setu-Nonce']!,
        parts: [await RequestSigner.sha256Hex(seen.bodyBytes)],
      );
      expect(await SigningService().verify(canonical, h['X-Setu-Sender']!, h['X-Setu-Signature']!), isTrue);
    });
  });
}

List<int> _hex(String hex) => [for (var i = 0; i < hex.length; i += 2) int.parse(hex.substring(i, i + 2), radix: 16)];
