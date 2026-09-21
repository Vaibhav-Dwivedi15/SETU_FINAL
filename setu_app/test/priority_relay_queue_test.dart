import 'package:flutter_test/flutter_test.dart';
import 'package:setu_app/mesh/enums/emergency_priority.dart';
import 'package:setu_app/mesh/models/ack_packet.dart';
import 'package:setu_app/mesh/models/alert_packet.dart';
import 'package:setu_app/mesh/models/emergency_packet.dart';
import 'package:setu_app/mesh/models/termination_packet.dart';
import 'package:setu_app/mesh/services/priority_relay_queue.dart';

// Pure Dart logic tests — no device, no plugins, run with `flutter test`.
//
// The three properties PriorityRelayQueue claims, each tested directly:
//   1. CRITICAL never waits behind a lower tier.
//   2. No tier starves forever.
//   3. It is bounded, and sheds the least important work first.
//
// Times are injected (`now:`) rather than slept through, so aging
// behaviour is deterministic and the suite stays fast.

EmergencyPacket emergency(
  String id, {
  EmergencyPriority priority = EmergencyPriority.high,
  String emergencyId = 'e1',
}) =>
    EmergencyPacket(
      packetId: id,
      senderId: 'sender-abc',
      timestamp: DateTime.utc(2026, 1, 1, 12),
      nonce: 'nonce-$id',
      ttl: 5,
      hopCount: 0,
      signature: 'sig',
      emergencyId: emergencyId,
      latitude: 25.1,
      longitude: 82.5,
      message: 'SOS',
      priority: priority,
    );

TerminationPacket termination(String id, {String emergencyId = 'e1'}) =>
    TerminationPacket(
      packetId: id,
      senderId: 'responder-key',
      timestamp: DateTime.utc(2026, 1, 1, 12),
      nonce: 'nonce-$id',
      ttl: 5,
      hopCount: 0,
      signature: 'sig',
      emergencyId: emergencyId,
      responderId: 'responder-1',
    );

AckPacket ack(String id, {String emergencyId = 'e1'}) => AckPacket(
      packetId: id,
      senderId: 'sender-abc',
      timestamp: DateTime.utc(2026, 1, 1, 12),
      nonce: 'nonce-$id',
      ttl: 5,
      hopCount: 0,
      signature: 'sig',
      originalPacketId: 'orig',
      emergencyId: emergencyId,
    );

AlertPacket alert(String id) => AlertPacket(
      packetId: id,
      senderId: 'sender-abc',
      timestamp: DateTime.utc(2026, 1, 1, 12),
      nonce: 'nonce-$id',
      ttl: 5,
      hopCount: 0,
      signature: 'sig',
      incidentType: 'flood',
      latitude: 25.1,
      longitude: 82.5,
    );

void main() {
  final t0 = DateTime.utc(2026, 1, 1, 12);

  group('classification', () {
    test('every packet type lands in the tier its meaning deserves', () {
      expect(PriorityRelayQueue.priorityOf(emergency('p', priority: EmergencyPriority.critical)),
          EmergencyPriority.critical);
      expect(PriorityRelayQueue.priorityOf(emergency('p', priority: EmergencyPriority.low)),
          EmergencyPriority.low);
      expect(PriorityRelayQueue.priorityOf(termination('t')), EmergencyPriority.critical,
          reason: 'termination stops the whole mesh relaying a closed incident');
      expect(PriorityRelayQueue.priorityOf(ack('a')), EmergencyPriority.high);
      expect(PriorityRelayQueue.priorityOf(alert('al')), EmergencyPriority.medium);
    });
  });

  group('property 1 — CRITICAL never waits behind a lower tier', () {
    test('a critical packet queued last is dequeued first', () {
      final queue = PriorityRelayQueue();
      queue.enqueue(alert('low-ish'), now: t0);
      queue.enqueue(emergency('medium', priority: EmergencyPriority.medium), now: t0);
      queue.enqueue(emergency('high', priority: EmergencyPriority.high), now: t0);
      queue.enqueue(emergency('critical', priority: EmergencyPriority.critical), now: t0);

      expect(queue.dequeue(now: t0)!.packet.packetId, 'critical');
    });

    test('full drain order is strictly by priority', () {
      final queue = PriorityRelayQueue();
      queue.enqueue(emergency('l', priority: EmergencyPriority.low), now: t0);
      queue.enqueue(emergency('c', priority: EmergencyPriority.critical), now: t0);
      queue.enqueue(emergency('m', priority: EmergencyPriority.medium), now: t0);
      queue.enqueue(emergency('h', priority: EmergencyPriority.high), now: t0);

      final order = <String>[];
      while (queue.isNotEmpty) {
        order.add(queue.dequeue(now: t0)!.packet.packetId);
      }
      expect(order, ['c', 'h', 'm', 'l']);
    });

    test('a critical packet arriving mid-burst preempts everything already queued', () {
      final queue = PriorityRelayQueue();
      for (var i = 0; i < 20; i++) {
        queue.enqueue(emergency('routine$i', priority: EmergencyPriority.medium), now: t0);
      }
      // Radio has drained two routine packets; an SOS now arrives.
      queue.dequeue(now: t0);
      queue.dequeue(now: t0);
      queue.enqueue(emergency('sos', priority: EmergencyPriority.critical), now: t0);

      expect(queue.dequeue(now: t0)!.packet.packetId, 'sos',
          reason: 'SOS sat behind 18 routine packets — the exact failure this queue exists to prevent');
    });

    test('FIFO is preserved inside a tier', () {
      final queue = PriorityRelayQueue();
      queue.enqueue(emergency('first', priority: EmergencyPriority.high), now: t0);
      queue.enqueue(emergency('second', priority: EmergencyPriority.high), now: t0);
      queue.enqueue(emergency('third', priority: EmergencyPriority.high), now: t0);

      expect(queue.dequeue(now: t0)!.packet.packetId, 'first');
      expect(queue.dequeue(now: t0)!.packet.packetId, 'second');
      expect(queue.dequeue(now: t0)!.packet.packetId, 'third');
    });
  });

  group('property 2 — no tier starves forever', () {
    test('a long-waiting low packet ages ahead of a freshly queued medium', () {
      final queue = PriorityRelayQueue(agingThreshold: const Duration(seconds: 2));
      queue.enqueue(emergency('old-low', priority: EmergencyPriority.low), now: t0);
      final later = t0.add(const Duration(seconds: 6));
      queue.enqueue(emergency('new-medium', priority: EmergencyPriority.medium), now: later);

      expect(queue.dequeue(now: later)!.packet.packetId, 'old-low');
    });

    test('aging stops at HIGH — an aged packet can never outrank a real SOS', () {
      final queue = PriorityRelayQueue(agingThreshold: const Duration(seconds: 1));
      queue.enqueue(emergency('ancient-low', priority: EmergencyPriority.low), now: t0);
      final muchLater = t0.add(const Duration(hours: 3));
      queue.enqueue(emergency('fresh-sos', priority: EmergencyPriority.critical), now: muchLater);

      expect(queue.dequeue(now: muchLater)!.packet.packetId, 'fresh-sos',
          reason: 'aging must never promote routine traffic into the critical tier');
    });

    test('waited duration is reported at dequeue, per tier', () {
      final queue = PriorityRelayQueue();
      queue.enqueue(emergency('p', priority: EmergencyPriority.medium), now: t0);
      final entry = queue.dequeue(now: t0.add(const Duration(milliseconds: 250)))!;
      expect(entry.waited, const Duration(milliseconds: 250));
      expect(entry.priority, EmergencyPriority.medium);
    });
  });

  group('property 3 — bounded, and sheds the least important work first', () {
    test('a full queue of criticals refuses a low packet rather than evicting one', () {
      final queue = PriorityRelayQueue(maxSize: 3);
      for (var i = 0; i < 3; i++) {
        expect(queue.enqueue(emergency('c$i', priority: EmergencyPriority.critical), now: t0), isTrue);
      }
      expect(queue.enqueue(emergency('late-low', priority: EmergencyPriority.low), now: t0), isFalse);
      expect(queue.length, 3);
      expect(queue.lengthOf(EmergencyPriority.critical), 3);
      expect(queue.droppedByOverflow, 1);
    });

    test('a full queue of low traffic makes room for a critical packet', () {
      final queue = PriorityRelayQueue(maxSize: 3);
      for (var i = 0; i < 3; i++) {
        queue.enqueue(emergency('l$i', priority: EmergencyPriority.low), now: t0);
      }
      expect(queue.enqueue(emergency('sos', priority: EmergencyPriority.critical), now: t0), isTrue);
      expect(queue.lengthOf(EmergencyPriority.critical), 1);
      expect(queue.lengthOf(EmergencyPriority.low), 2, reason: 'oldest low packet should be the one sacrificed');
      expect(queue.dequeue(now: t0)!.packet.packetId, 'sos');
    });

    test('overflow is counted, never silent', () {
      final queue = PriorityRelayQueue(maxSize: 2);
      queue.enqueue(emergency('a', priority: EmergencyPriority.low), now: t0);
      queue.enqueue(emergency('b', priority: EmergencyPriority.low), now: t0);
      queue.enqueue(emergency('c', priority: EmergencyPriority.low), now: t0);
      expect(queue.droppedByOverflow, greaterThan(0));
      expect(queue.depthSnapshot()['droppedByOverflow'], queue.droppedByOverflow);
    });

    test('queue never exceeds maxSize under sustained flood', () {
      final queue = PriorityRelayQueue(maxSize: 10);
      for (var i = 0; i < 500; i++) {
        queue.enqueue(
          emergency('p$i',
              priority: EmergencyPriority.values[i % EmergencyPriority.values.length]),
          now: t0,
        );
        expect(queue.length, lessThanOrEqualTo(10));
      }
    });
  });

  group('termination sweeps the in-memory queue too', () {
    test('removeEmergency drops that incident\'s packets and its acks', () {
      final queue = PriorityRelayQueue();
      queue.enqueue(emergency('e1-a', emergencyId: 'e1'), now: t0);
      queue.enqueue(emergency('e1-b', emergencyId: 'e1'), now: t0);
      queue.enqueue(ack('e1-ack', emergencyId: 'e1'), now: t0);
      queue.enqueue(emergency('e2-a', emergencyId: 'e2'), now: t0);

      final removed = queue.removeEmergency('e1');

      expect(removed, 3);
      expect(queue.length, 1);
      expect(queue.dequeue(now: t0)!.packet.packetId, 'e2-a');
    });

    test('removing an unknown emergency changes nothing', () {
      final queue = PriorityRelayQueue();
      queue.enqueue(emergency('e1-a', emergencyId: 'e1'), now: t0);
      expect(queue.removeEmergency('does-not-exist'), 0);
      expect(queue.length, 1);
    });
  });

  group('decide()', () {
    test('power saver blocks relay and says why', () {
      final decision = PriorityRelayQueue.decide(
        packet: emergency('p'),
        allowRelay: false,
        allowUpload: false,
      );
      expect(decision.relay, isFalse);
      expect(decision.reason, contains('power saver'));
    });

    test('ack and alert are relayed but never uploaded', () {
      final ackDecision = PriorityRelayQueue.decide(
        packet: ack('a'),
        allowRelay: true,
        allowUpload: true,
      );
      expect(ackDecision.relay, isTrue);
      expect(ackDecision.upload, isFalse);

      final alertDecision = PriorityRelayQueue.decide(
        packet: alert('al'),
        allowRelay: true,
        allowUpload: true,
      );
      expect(alertDecision.relay, isTrue);
      expect(alertDecision.upload, isFalse);
    });

    test('an emergency packet is both relayed and uploaded when policy allows', () {
      final decision = PriorityRelayQueue.decide(
        packet: emergency('p'),
        allowRelay: true,
        allowUpload: true,
      );
      expect(decision.relay, isTrue);
      expect(decision.upload, isTrue);
      expect(decision.reason, contains('high'));
    });
  });
}
