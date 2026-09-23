import '../../security/security_constants.dart';
import '../enums/emergency_priority.dart';

/// PRIORITY 3 -- adaptive TTL.
///
/// The existing behaviour is a flat `ttl - 1` per hop, everywhere
/// (MeshPacket.withRelayHop in Dart, PacketRelayEngine.process in
/// Kotlin). That is safe but undifferentiated: a three-hour-stale
/// community alert bouncing around a dense cluster gets exactly the same
/// hop budget as a fresh CRITICAL SOS.
///
/// IMPORTANT -- the direction of "adaptive" here.
///
/// SecurityConstants has defaultTTL == maxTTL == 5. A packet is born at
/// the ceiling, so there is no headroom to extend anything, and the
/// session rules are explicit: maxTTL is a hard upper bound, never raise
/// TTL globally, never create infinite propagation. Therefore this class
/// only ever decrements by 1 OR MORE. It makes low-value traffic die
/// SOONER so the radio, the queue and the battery are left for traffic
/// that matters -- it never makes anything live longer.
///
/// Concretely, relative to the old flat rule:
///   * CRITICAL packets: identical behaviour, exactly -1 per hop. Their
///     full 5-hop budget is never shortened, under any condition.
///   * everything else: -1 normally, -2 when the packet is already stale,
///     -2 when the local cluster is dense enough that flooding has almost
///     certainly already covered it.
///
/// Invariants (asserted in test/adaptive_ttl_test.dart):
///   * result <= SecurityConstants.maxTTL, ALWAYS, including for a
///     malformed or hostile packet arriving with ttl = 9999.
///   * result < input ttl, ALWAYS. No hop is ever free, so no packet can
///     circulate forever.
///   * result >= 0.
///
/// BLOCK 1 NOTE: in production the relay TTL is computed ONLY by the
/// native engine (PacketRelayEngine.nextTtl -- see
/// NearbyService.relaysNatively), which mirrors this class WITHOUT the
/// dense-cluster decrement (native does not track a peer census the way
/// MeshServiceImpl does). This class now only decides relay TTL for
/// transports that have no native engine (the test simulation), so two
/// different TTLs can no longer be produced for the same packet.
class AdaptiveTtl {
  const AdaptiveTtl._();

  /// A packet older than this fraction of the maximum accepted packet age
  /// is treated as stale. It has not been expired by PacketValidator yet
  /// (that still happens at SecurityConstants.maxPacketAge and is NOT
  /// bypassed here) -- it is simply unlikely to still be worth flooding.
  static const double staleAgeFraction = 0.6;

  /// Connected-peer count at or above which the local cluster counts as
  /// dense. In a dense cluster a packet reaches most devices via several
  /// paths at once, so spending the last hops of a LOW/MEDIUM packet's
  /// budget there buys very little.
  static const int densePeerThreshold = 6;

  static Duration get _staleAfter => Duration(
        microseconds:
            (SecurityConstants.maxPacketAge.inMicroseconds * staleAgeFraction).round(),
      );

  /// TTL a relayed copy of this packet should carry.
  ///
  /// [connectedPeerCount] is optional: when the caller has no idea how
  /// many peers are connected (Dart does not always know -- the native
  /// layer owns the endpoint set), pass null and density simply does not
  /// influence the decision. Missing information must never make the
  /// rule more aggressive.
  static int nextTtl({
    required int currentTtl,
    required Duration packetAge,
    required EmergencyPriority priority,
    int hopCount = 0,
    int? connectedPeerCount,
  }) {
    // Clamp the INPUT first. A packet arriving with ttl above the
    // ceiling is either a version mismatch or someone trying to buy
    // themselves unlimited propagation; either way it gets the ceiling,
    // not what it asked for.
    var ttl = currentTtl;
    if (ttl > SecurityConstants.maxTTL) ttl = SecurityConstants.maxTTL;
    if (ttl <= 0) return 0;

    var decrement = 1;

    if (priority != EmergencyPriority.critical) {
      if (packetAge >= _staleAfter) {
        decrement += 1;
      }
      if (priority != EmergencyPriority.high &&
          connectedPeerCount != null &&
          connectedPeerCount >= densePeerThreshold) {
        decrement += 1;
      }
    }

    final next = ttl - decrement;
    if (next <= 0) return 0;

    // Belt and braces: the result can never exceed the ceiling or the
    // value we were given. Both are already guaranteed above; this is
    // here so that a future edit to the rules above cannot silently
    // break the invariant.
    final ceiling = SecurityConstants.maxTTL < ttl - 1 ? SecurityConstants.maxTTL : ttl - 1;
    return next > ceiling ? ceiling : next;
  }

  /// Whether a packet carrying [ttl] may still be forwarded. Mirrors the
  /// existing check in MeshService._relayPacket rather than replacing it.
  static bool canRelay(int ttl) => ttl >= SecurityConstants.minimumTTL;

  /// Human-readable justification, for relay logs and tests.
  static String explain({
    required int currentTtl,
    required int nextTtl,
    required EmergencyPriority priority,
    required Duration packetAge,
    int? connectedPeerCount,
  }) {
    final spent = currentTtl - nextTtl;
    if (priority == EmergencyPriority.critical) {
      return 'ttl $currentTtl->$nextTtl (critical: full hop budget preserved)';
    }
    if (spent <= 1) {
      return 'ttl $currentTtl->$nextTtl (standard hop)';
    }
    final reasons = <String>[];
    if (packetAge >= _staleAfter) reasons.add('stale ${packetAge.inSeconds}s');
    if (connectedPeerCount != null && connectedPeerCount >= densePeerThreshold) {
      reasons.add('dense cluster ($connectedPeerCount peers)');
    }
    return 'ttl $currentTtl->$nextTtl (accelerated: ${reasons.join(', ')})';
  }
}
