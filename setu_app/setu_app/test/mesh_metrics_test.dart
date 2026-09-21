import 'package:flutter_test/flutter_test.dart';
import 'package:setu_app/mesh/services/mesh_metrics.dart';

// Pure Dart logic tests — no device, no plugins, run with `flutter test`.
//
// The single most important property here: an UNMEASURED stage must
// report null, never 0. A zero that means "never measured" is how fake
// performance numbers end up in a presentation, which the engineering
// brief explicitly forbids.

void main() {
  setUp(MeshMetrics.instance.reset);
  tearDown(MeshMetrics.instance.reset);

  group('LatencySamples', () {
    test('reports nothing at all before any sample', () {
      final samples = LatencySamples('test');
      expect(samples.count, 0);
      expect(samples.averageMicros, isNull);
      expect(samples.medianMicros, isNull);
      expect(samples.p95Micros, isNull);
      expect(samples.toString(), contains('not measured'));
      expect(samples.snapshot()['min'], isNull);
      expect(samples.snapshot()['max'], isNull);
    });

    test('tracks count, sum, min and max', () {
      final samples = LatencySamples('test')
        ..addMicros(100)
        ..addMicros(300)
        ..addMicros(200);

      expect(samples.count, 3);
      expect(samples.totalMicros, 600);
      expect(samples.averageMicros, 200);
      expect(samples.minMicros, 100);
      expect(samples.maxMicros, 300);
    });

    test('discards negative samples instead of flattering the average', () {
      final samples = LatencySamples('test')
        ..addMicros(100)
        ..addMicros(-5000); // two devices' clocks disagree

      expect(samples.count, 1, reason: 'a negative latency is not a fast packet');
      expect(samples.averageMicros, 100);
    });

    test('percentiles come from the recent window and stay bounded', () {
      final samples = LatencySamples('test');
      for (var i = 1; i <= 1000; i++) {
        samples.addMicros(i);
      }
      expect(samples.count, 1000);
      expect(samples.medianMicros, isNotNull);
      expect(samples.p95Micros, greaterThanOrEqualTo(samples.medianMicros!));
      // Ring is capped, so memory does not grow with traffic.
      expect(samples.p95Micros, greaterThan(900));
    });

    test('time() records the duration of an async action', () async {
      final samples = LatencySamples('test');
      final result = await samples.time(() async {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        return 'done';
      });
      expect(result, 'done');
      expect(samples.count, 1);
      expect(samples.maxMicros, greaterThan(0));
    });

    test('time() still records when the action throws', () async {
      final samples = LatencySamples('test');
      await expectLater(
        samples.time(() async => throw StateError('boom')),
        throwsStateError,
      );
      expect(samples.count, 1);
    });
  });

  group('MeshMetrics — unmeasured is null, not zero', () {
    test('a fresh instance reports every rate as not measured', () {
      final metrics = MeshMetrics.instance;
      expect(metrics.duplicateRate, isNull);
      expect(metrics.relaySuccessRate, isNull);
      expect(metrics.localDropRate, isNull);
      expect(metrics.batteryDelta, isNull);
      expect(metrics.discoveryLatencyMicros, isNull);
      expect(metrics.connectionLatencyMicros, isNull);
      expect(metrics.report(), contains('not measured'));
    });

    test('rates are computed once there is a denominator', () {
      final metrics = MeshMetrics.instance
        ..relayAttempts = 10
        ..relayFailures = 2
        ..received = 8
        ..dropped = 2;

      expect(metrics.relaySuccessRate, 0.8);
      expect(metrics.localDropRate, 0.2);
    });

    test('duplicate rate needs the native denominator', () {
      final metrics = MeshMetrics.instance;
      expect(metrics.duplicateRate, isNull);

      metrics.applyNativeStats({'totalProcessed': 100, 'duplicatesFiltered': 25});
      expect(metrics.duplicateRate, 0.25);
    });
  });

  group('applyNativeStats tolerates an older native build', () {
    test('missing keys leave those metrics unmeasured rather than zeroed', () {
      final metrics = MeshMetrics.instance..applyNativeStats({});
      expect(metrics.discoveryLatencyMicros, isNull);
      expect(metrics.connectionLatencyMicros, isNull);
      expect(metrics.duplicateRate, isNull);
    });

    test('a native zero timing is treated as unmeasured, not as 0ms', () {
      final metrics = MeshMetrics.instance
        ..applyNativeStats({
          'discoveryLatencyMicros': 0,
          'connectionLatencyMicros': 0,
        });
      expect(metrics.discoveryLatencyMicros, isNull,
          reason: '0 is the native "never measured" sentinel');
      expect(metrics.connectionLatencyMicros, isNull);
    });

    test('wrong types are ignored instead of crashing the relay path', () {
      final metrics = MeshMetrics.instance
        ..applyNativeStats({
          'totalProcessed': 'not-a-number',
          'duplicatesFiltered': null,
        });
      expect(metrics.nativeTotalProcessed, 0);
      expect(metrics.duplicateRate, isNull);
    });

    test('real values are applied', () {
      final metrics = MeshMetrics.instance
        ..applyNativeStats({
          'totalProcessed': 40,
          'duplicatesFiltered': 10,
          'relaySuppressed': 4,
          'discoveryLatencyMicros': 1500000,
          'connectionLatencyMicros': 800000,
        });
      expect(metrics.nativeTotalProcessed, 40);
      expect(metrics.duplicatesFiltered, 10);
      expect(metrics.relaySuppressed, 4);
      expect(metrics.discoveryLatencyMicros, 1500000);
      expect(metrics.connectionLatencyMicros, 800000);
    });
  });

  group('queue wait is recorded per priority', () {
    test('per-tier samples are kept separately from the aggregate', () {
      final metrics = MeshMetrics.instance
        ..recordQueueWait('critical', const Duration(milliseconds: 2))
        ..recordQueueWait('low', const Duration(milliseconds: 400))
        ..recordQueueWait('low', const Duration(milliseconds: 600));

      expect(metrics.queueWait.count, 3);
      expect(metrics.queueWaitByPriority['critical']!.count, 1);
      expect(metrics.queueWaitByPriority['low']!.count, 2);
      expect(
        metrics.queueWaitByPriority['critical']!.averageMicros,
        lessThan(metrics.queueWaitByPriority['low']!.averageMicros!),
        reason: 'this comparison IS the priority-queue claim, measured',
      );
    });
  });

  group('battery', () {
    test('delta is only reported once there is a baseline', () {
      final metrics = MeshMetrics.instance;
      expect(metrics.batteryDelta, isNull);

      metrics.recordBattery(87);
      expect(metrics.batteryDelta, 0);

      metrics.recordBattery(83);
      expect(metrics.batteryDelta, 4, reason: 'positive delta means drain');
      expect(metrics.batteryAtFirstSample, 87, reason: 'baseline must not move');
    });
  });

  group('snapshot()', () {
    test('is machine-readable and keeps unmeasured values null', () {
      final snapshot = MeshMetrics.instance.snapshot();
      expect(snapshot['counters'], isA<Map>());
      expect((snapshot['rates'] as Map)['duplicateRate'], isNull);
      expect(((snapshot['latencyMicros'] as Map)['endToEnd'] as Map)['avg'], isNull);
    });
  });

  group('existing counters keep working (regression guard)', () {
    test('the original five counters and reset are unchanged', () {
      final metrics = MeshMetrics.instance;
      metrics.sent++;
      metrics.received++;
      metrics.relayed++;
      metrics.uploaded++;
      metrics.dropped++;
      expect([metrics.sent, metrics.received, metrics.relayed, metrics.uploaded, metrics.dropped],
          [1, 1, 1, 1, 1]);

      metrics.reset();
      expect([metrics.sent, metrics.received, metrics.relayed, metrics.uploaded, metrics.dropped],
          [0, 0, 0, 0, 0]);
      expect(metrics.signatureVerify.count, 0, reason: 'reset must clear latency samples too');
    });

    test('changes stream still emits on notify', () async {
      final metrics = MeshMetrics.instance;
      final future = metrics.changes.first;
      metrics.notify();
      await expectLater(future, completes);
    });
  });
}
