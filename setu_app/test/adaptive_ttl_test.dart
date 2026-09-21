import 'package:flutter_test/flutter_test.dart';
import 'package:setu_app/mesh/enums/emergency_priority.dart';
import 'package:setu_app/mesh/services/adaptive_ttl.dart';
import 'package:setu_app/security/security_constants.dart';

// Pure Dart logic tests — no device, no plugins, run with `flutter test`.
//
// These exist to hold the three invariants AdaptiveTtl claims, because
// getting TTL wrong is the difference between "flood control" and "a
// packet circulating the mesh forever". Every case the session brief
// listed is covered: normal packet, old packet, high-hop packet, expired
// packet, max TTL, malformed TTL, repeated relay.

void main() {
  const fresh = Duration(seconds: 5);
  final stale = SecurityConstants.maxPacketAge * 0.8; // past staleAgeFraction

  group('AdaptiveTtl invariants — must hold for every possible input', () {
    test('result never exceeds maxTTL, even for a hostile ttl', () {
      for (final claimedTtl in [6, 10, 99, 9999, 1 << 30]) {
        for (final priority in EmergencyPriority.values) {
          final next = AdaptiveTtl.nextTtl(
            currentTtl: claimedTtl,
            packetAge: fresh,
            priority: priority,
          );
          expect(
            next,
            lessThanOrEqualTo(SecurityConstants.maxTTL),
            reason: 'ttl=$claimedTtl priority=$priority escaped the ceiling',
          );
        }
      }
    });

    test('result is always strictly less than the incoming ttl — no free hops', () {
      for (var ttl = 1; ttl <= SecurityConstants.maxTTL; ttl++) {
        for (final priority in EmergencyPriority.values) {
          for (final age in [fresh, stale]) {
            final next = AdaptiveTtl.nextTtl(
              currentTtl: ttl,
              packetAge: age,
              priority: priority,
            );
            expect(next, lessThan(ttl),
                reason: 'ttl=$ttl priority=$priority age=$age did not decrease');
          }
        }
      }
    });

    test('result is never negative', () {
      for (final ttl in [-5, -1, 0, 1]) {
        final next = AdaptiveTtl.nextTtl(
          currentTtl: ttl,
          packetAge: stale,
          priority: EmergencyPriority.low,
        );
        expect(next, greaterThanOrEqualTo(0));
      }
    });
  });

  group('CRITICAL traffic is never penalised', () {
    test('critical keeps the old flat -1 regardless of age or density', () {
      for (var ttl = 1; ttl <= SecurityConstants.maxTTL; ttl++) {
        expect(
          AdaptiveTtl.nextTtl(
            currentTtl: ttl,
            packetAge: stale,
            priority: EmergencyPriority.critical,
            connectedPeerCount: 50,
          ),
          ttl - 1,
          reason: 'critical packet lost more than one hop of budget',
        );
      }
    });

    test('a critical packet still gets its full hop budget across repeated relays', () {
      var ttl = SecurityConstants.defaultTTL;
      var hops = 0;
      while (AdaptiveTtl.canRelay(ttl)) {
        ttl = AdaptiveTtl.nextTtl(
          currentTtl: ttl,
          packetAge: stale,
          priority: EmergencyPriority.critical,
          connectedPeerCount: 20,
        );
        hops++;
        expect(hops, lessThan(20), reason: 'repeated relay did not terminate');
      }
      // 5 -> 4 -> 3 -> 2 -> 1 -> 0: five relays, then TTL exhausted.
      expect(hops, SecurityConstants.defaultTTL);
    });
  });

  group('non-critical traffic expires faster when it is worth less', () {
    test('a stale low-priority packet loses two hops, not one', () {
      expect(
        AdaptiveTtl.nextTtl(
          currentTtl: 5,
          packetAge: stale,
          priority: EmergencyPriority.low,
        ),
        3,
      );
    });

    test('a fresh low-priority packet in a sparse cluster behaves as before', () {
      expect(
        AdaptiveTtl.nextTtl(
          currentTtl: 5,
          packetAge: fresh,
          priority: EmergencyPriority.low,
          connectedPeerCount: 1,
        ),
        4,
      );
    });

    test('density accelerates low/medium but never high', () {
      final dense = AdaptiveTtl.densePeerThreshold + 2;

      expect(
        AdaptiveTtl.nextTtl(
          currentTtl: 5,
          packetAge: fresh,
          priority: EmergencyPriority.medium,
          connectedPeerCount: dense,
        ),
        3,
        reason: 'medium priority should shed a hop in a dense cluster',
      );

      expect(
        AdaptiveTtl.nextTtl(
          currentTtl: 5,
          packetAge: fresh,
          priority: EmergencyPriority.high,
          connectedPeerCount: dense,
        ),
        4,
        reason: 'high priority must not be penalised for density alone',
      );
    });

    test('unknown peer count never makes the rule more aggressive', () {
      final withoutInfo = AdaptiveTtl.nextTtl(
        currentTtl: 5,
        packetAge: fresh,
        priority: EmergencyPriority.low,
        connectedPeerCount: null,
      );
      expect(withoutInfo, 4);
    });

    test('every non-critical packet terminates under repeated relay', () {
      for (final priority in [
        EmergencyPriority.low,
        EmergencyPriority.medium,
        EmergencyPriority.high,
      ]) {
        var ttl = SecurityConstants.maxTTL;
        var hops = 0;
        while (AdaptiveTtl.canRelay(ttl)) {
          ttl = AdaptiveTtl.nextTtl(
            currentTtl: ttl,
            packetAge: stale,
            priority: priority,
            connectedPeerCount: 10,
          );
          hops++;
          expect(hops, lessThan(20),
              reason: '$priority packet propagated without terminating');
        }
      }
    });
  });

  group('expiry and malformed input', () {
    test('an exhausted packet stays exhausted', () {
      expect(
        AdaptiveTtl.nextTtl(
          currentTtl: 0,
          packetAge: fresh,
          priority: EmergencyPriority.critical,
        ),
        0,
      );
      expect(AdaptiveTtl.canRelay(0), isFalse);
    });

    test('canRelay mirrors SecurityConstants.minimumTTL and is not bypassed', () {
      expect(AdaptiveTtl.canRelay(SecurityConstants.minimumTTL), isTrue);
      expect(AdaptiveTtl.canRelay(SecurityConstants.minimumTTL - 1), isFalse);
    });

    test('a packet claiming ttl 9999 is clamped, not honoured', () {
      final next = AdaptiveTtl.nextTtl(
        currentTtl: 9999,
        packetAge: fresh,
        priority: EmergencyPriority.critical,
      );
      expect(next, SecurityConstants.maxTTL - 1);
    });

    test('hopCount is accepted but never lets TTL grow', () {
      for (final hop in [0, 1, 5, 50]) {
        final next = AdaptiveTtl.nextTtl(
          currentTtl: 4,
          packetAge: fresh,
          priority: EmergencyPriority.high,
          hopCount: hop,
        );
        expect(next, lessThan(4));
      }
    });
  });

  group('explain()', () {
    test('names the reason a packet was accelerated', () {
      final text = AdaptiveTtl.explain(
        currentTtl: 5,
        nextTtl: 3,
        priority: EmergencyPriority.low,
        packetAge: stale,
        connectedPeerCount: 1,
      );
      expect(text, contains('accelerated'));
      expect(text, contains('stale'));
    });

    test('says explicitly that critical budget was preserved', () {
      final text = AdaptiveTtl.explain(
        currentTtl: 5,
        nextTtl: 4,
        priority: EmergencyPriority.critical,
        packetAge: stale,
      );
      expect(text, contains('critical'));
    });
  });
}
