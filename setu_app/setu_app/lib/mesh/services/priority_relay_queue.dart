import 'dart:collection';

import '../enums/emergency_priority.dart';
import '../models/ack_packet.dart';
import '../models/alert_packet.dart';
import '../models/emergency_packet.dart';
import '../models/mesh_packet.dart';
import '../models/termination_packet.dart';
import 'mesh_constants.dart';
import 'relay_decision.dart';

/// PRIORITY 2 -- packet prioritisation for the relay path.
///
/// Before this, MeshService relayed strictly in arrival order: a routine
/// community AlertPacket that arrived first went out before a CRITICAL
/// SOS that arrived a millisecond later. On a quiet mesh that costs
/// nothing; during an actual disaster, when every device in range is
/// generating traffic, it is exactly the wrong behaviour.
///
/// Deliberately NOT a second policy system -- it reuses what already
/// exists:
///   * [EmergencyPriority] (mesh/enums) is the tier enum, already carried
///     on every EmergencyPacket and already on the wire.
///   * [MeshConstants.maxRelayQueue] is the bound (was dead code).
///   * [RelayDecision] (was dead code) is what [decide] returns, so the
///     relay/upload/reason triple has one shape across the codebase.
///
/// It is also NOT the durable queue: [LocalQueueService] persists packets
/// to SQLite for store-and-forward across restarts and is untouched. This
/// one is in-memory, short-lived, and only orders the next few hops.
///
/// Three properties it has to hold, all covered by tests in
/// test/priority_relay_queue_test.dart:
///   1. CRITICAL never waits behind a lower tier.
///   2. No tier starves forever -- lower tiers age upward (but never INTO
///      critical, so aged routine traffic can never compete with a real
///      SOS).
///   3. It is bounded. Under flood it drops the lowest-priority oldest
///      thing, never a critical packet, and says so.
class PriorityRelayQueue {
  PriorityRelayQueue({
    this.maxSize = MeshConstants.maxRelayQueue,
    this.agingThreshold = const Duration(seconds: 2),
  });

  /// Hard bound on queued relays. A mesh under flood must shed load
  /// somewhere; doing it here, deliberately and by priority, is better
  /// than an unbounded queue that eventually takes the process down.
  final int maxSize;

  /// How long a packet must wait before it is treated as one tier more
  /// urgent than it really is. Anti-starvation only -- see [_effectiveRank].
  final Duration agingThreshold;

  final Map<EmergencyPriority, ListQueue<QueuedRelay>> _tiers = {
    for (final priority in EmergencyPriority.values) priority: ListQueue<QueuedRelay>(),
  };

  int _droppedByOverflow = 0;

  /// Packets discarded because the queue was full. Surfaced so overflow
  /// shows up as a number in the metrics rather than as silent loss.
  int get droppedByOverflow => _droppedByOverflow;

  int get length => _tiers.values.fold(0, (sum, queue) => sum + queue.length);

  bool get isEmpty => length == 0;

  bool get isNotEmpty => !isEmpty;

  int lengthOf(EmergencyPriority priority) => _tiers[priority]!.length;

  /// Tier a packet belongs to.
  ///
  /// EmergencyPacket carries its own priority (already on the wire).
  /// The other three types don't, so they are classified by what they
  /// mean, not by guessing:
  ///   * TerminationPacket -> CRITICAL. It is how a verified responder
  ///     tells the mesh to STOP relaying an incident; delaying it makes
  ///     every other device work harder for longer.
  ///   * AckPacket -> HIGH. Small, and it is what stops the originator
  ///     re-sending an SOS it thinks was never delivered.
  ///   * AlertPacket -> MEDIUM. Community/volunteer broadcast: useful,
  ///     not life-critical.
  static EmergencyPriority priorityOf(MeshPacket packet) {
    if (packet is EmergencyPacket) return packet.priority;
    if (packet is TerminationPacket) return EmergencyPriority.critical;
    if (packet is AckPacket) return EmergencyPriority.high;
    if (packet is AlertPacket) return EmergencyPriority.medium;
    return EmergencyPriority.medium;
  }

  /// Whether this packet should be queued for relay at all, and why.
  /// Returns the previously-unused [RelayDecision] so the reason string
  /// can be logged and asserted on instead of being buried in a bool.
  static RelayDecision decide({
    required MeshPacket packet,
    required bool allowRelay,
    required bool allowUpload,
  }) {
    if (!allowRelay) {
      return const RelayDecision(
        relay: false,
        upload: false,
        reason: 'power saver: relay disabled by MeshPolicy',
      );
    }
    // Ack and Alert are terminal for upload purposes -- MeshService has
    // always excluded them from backend upload; keeping that decision
    // expressed here means there is one place to read it.
    final uploadable = allowUpload && packet is! AckPacket && packet is! AlertPacket;
    return RelayDecision(
      relay: true,
      upload: uploadable,
      reason: 'queued as ${priorityOf(packet).name}',
    );
  }

  /// Adds a packet. Returns false only if it could not be accepted
  /// (queue full of equal-or-higher priority work).
  bool enqueue(MeshPacket packet, {DateTime? now}) {
    final priority = priorityOf(packet);
    final entry = QueuedRelay(
      packet: packet,
      priority: priority,
      enqueuedAt: now ?? DateTime.now(),
    );

    if (length >= maxSize && !_makeRoomFor(priority)) {
      _droppedByOverflow++;
      return false;
    }

    _tiers[priority]!.addLast(entry);
    return true;
  }

  /// Evicts the oldest entry from the lowest-priority tier that is
  /// strictly below [incoming]. Critical entries are never evicted. If
  /// nothing outranks-downward, the incoming packet is the one refused.
  bool _makeRoomFor(EmergencyPriority incoming) {
    for (final candidate in EmergencyPriority.values) {
      // EmergencyPriority is declared low, medium, high, critical -- so
      // index order is already lowest-first, which is the order we want
      // to sacrifice in.
      if (candidate.index >= incoming.index) break;
      if (candidate == EmergencyPriority.critical) continue;
      final tier = _tiers[candidate]!;
      if (tier.isNotEmpty) {
        tier.removeFirst();
        _droppedByOverflow++;
        return true;
      }
    }
    return false;
  }

  /// Highest-priority packet, oldest first inside a tier, with aging
  /// applied so lower tiers cannot starve indefinitely.
  QueuedRelay? dequeue({DateTime? now}) {
    final at = now ?? DateTime.now();

    QueuedRelay? best;
    int bestRank = -1;

    for (final priority in EmergencyPriority.values) {
      final tier = _tiers[priority]!;
      if (tier.isEmpty) continue;
      final head = tier.first;
      final rank = _effectiveRank(head, at);

      if (rank > bestRank ||
          (rank == bestRank && best != null && head.enqueuedAt.isBefore(best.enqueuedAt))) {
        best = head;
        bestRank = rank;
      }
    }

    if (best == null) return null;
    _tiers[best.priority]!.removeFirst();
    return best.dequeuedAt(at);
  }

  /// Base tier index, plus one step per [agingThreshold] waited, capped
  /// at HIGH.
  ///
  /// The cap is the important part: an aged LOW packet can reach HIGH and
  /// so will eventually go out, but it can never reach CRITICAL and
  /// therefore can never delay a real SOS. That keeps property (1) and
  /// property (2) from fighting each other.
  int _effectiveRank(QueuedRelay entry, DateTime now) {
    final base = entry.priority.index;
    if (entry.priority == EmergencyPriority.critical) return base;

    final waited = now.difference(entry.enqueuedAt);
    if (waited < agingThreshold || agingThreshold.inMicroseconds <= 0) return base;

    final steps = waited.inMicroseconds ~/ agingThreshold.inMicroseconds;
    final promoted = base + steps;
    return promoted > EmergencyPriority.high.index
        ? EmergencyPriority.high.index
        : promoted;
  }

  /// Drops every queued packet belonging to a resolved emergency. Called
  /// when a verified TerminationPacket arrives, mirroring what
  /// LocalQueueService.markEmergencyClosed does for the durable queue --
  /// without this, a closed incident's packets would keep relaying out
  /// of this in-memory queue after the durable one had been swept.
  int removeEmergency(String emergencyId) {
    var removed = 0;
    for (final tier in _tiers.values) {
      final keep = tier.where((entry) {
        final packet = entry.packet;
        final belongs = (packet is EmergencyPacket && packet.emergencyId == emergencyId) ||
            (packet is AckPacket && packet.emergencyId == emergencyId);
        if (belongs) removed++;
        return !belongs;
      }).toList();
      tier
        ..clear()
        ..addAll(keep);
    }
    return removed;
  }

  void clear() {
    for (final tier in _tiers.values) {
      tier.clear();
    }
  }

  Map<String, int> depthSnapshot() => {
        for (final priority in EmergencyPriority.values) priority.name: _tiers[priority]!.length,
        'droppedByOverflow': _droppedByOverflow,
      };
}

/// One packet waiting for its turn on the radio.
class QueuedRelay {
  QueuedRelay({
    required this.packet,
    required this.priority,
    required this.enqueuedAt,
    this.waited = Duration.zero,
  });

  final MeshPacket packet;
  final EmergencyPriority priority;
  final DateTime enqueuedAt;

  /// Filled in at dequeue time; fed straight into
  /// MeshMetrics.recordQueueWait so "did CRITICAL actually jump the
  /// queue" is a measured number per tier, not an assumption.
  final Duration waited;

  QueuedRelay dequeuedAt(DateTime now) => QueuedRelay(
        packet: packet,
        priority: priority,
        enqueuedAt: enqueuedAt,
        waited: now.difference(enqueuedAt),
      );
}
