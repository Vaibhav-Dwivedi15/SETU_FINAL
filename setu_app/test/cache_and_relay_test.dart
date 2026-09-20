import 'package:flutter_test/flutter_test.dart';
import 'package:setu_app/utils/helpers.dart';

// These test the standalone logic pieces that don't need platform plugins.
// Native-side relay logic (PacketRelayEngine.kt, dedup, TTL) is Kotlin, not
// covered by `flutter test` — that needs an instrumented/native test setup,
// flagged here as a gap rather than silently skipped.

void main() {
  group('IdGenerator', () {
    test('generates the requested byte length as hex (2 chars per byte)', () {
      final id = IdGenerator.generate(bytes: 16);
      expect(id.length, 32); // 16 bytes -> 32 hex chars
    });

    test('generates unique values across repeated calls', () {
      final ids = List.generate(200, (_) => IdGenerator.generate());
      final unique = ids.toSet();
      expect(unique.length, ids.length, reason: 'no collisions expected in 200 generations');
    });

    test('output is valid lowercase hex', () {
      final id = IdGenerator.generate();
      expect(RegExp(r'^[0-9a-f]+$').hasMatch(id), true);
    });
  });
}

/*
  KNOWN GAP — not covered by this file, flagged honestly rather than
  silently skipped:

  1. PacketRelayEngine.kt (native Kotlin: dedup-by-packetId, TTL check,
     rebroadcast) has no automated test coverage. This is the actual
     relay-loop-prevention logic and arguably matters more than anything
     tested above. Needs an Android instrumented test or a plain JVM unit
     test with a mocked NearbyConnectionsManager — out of scope for
     `flutter test`, someone should set this up separately.

  2. LocalQueueService (sqflite-backed) isn't tested here because it needs
     sqflite_common_ffi for a test-friendly in-memory database. Worth
     adding if store-and-forward correctness ever becomes a live bug
     source — right now it's untested, not verified-safe.

  3. SigningService / PacketValidator / ReplayProtectionService (Shaurya's
     module) have no tests included here since they weren't originally
     built by this session — whoever owns that module should confirm
     whether tests exist for nonce-replay detection and TTL bounds
     specifically, since those are the highest-value security tests to
     have and weren't visible in what was reviewed.
*/
