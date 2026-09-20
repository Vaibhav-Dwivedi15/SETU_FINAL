import 'dart:async';
import 'dart:developer' as developer;

/// Aug 5 2026: added a broadcast stream so a live relay-status screen
/// can react to counter changes instead of polling. The counters
/// themselves are unchanged (still plain ints incremented from
/// MeshService) -- callers that just do `MeshMetrics.instance.sent++`
/// keep working exactly as before. The new `notify()` call is what
/// pushes an update to any listening UI; MeshService calls it after
/// each counter change (see mesh_service.dart). Kept deliberately
/// simple (a single "something changed" tick, not per-field events) --
/// the relay screen just re-reads all five counters on each tick.
///
/// Sep 2026 (PRIORITY 1 -- latency instrumentation): the five counters
/// above tell you HOW MANY packets moved but nothing about HOW FAST,
/// which meant no measurable performance target could be stated for the
/// SIH submission without inventing numbers. This adds per-stage latency
/// sampling on top, deliberately additive:
///
///   * every existing field/method above is untouched, so nothing that
///     already reads MeshMetrics needs to change;
///   * samples are plain ints (microseconds) accumulated in a fixed-size
///     ring -- no allocation per packet beyond one int write, no timers,
///     no extra network traffic. Instrumentation that slows the mesh
///     down would defeat its own purpose;
///   * end-to-end latency reuses the `timestamp` field ALREADY on every
///     MeshPacket (see mesh_packet.dart toJson()). No wire-format change,
///     no extra bytes on the air.
///
/// Honest limitations, stated here so they can't quietly become fake
/// claims in a presentation:
///   * end-to-end latency depends on sender/receiver clock agreement.
///     PacketValidator already rejects anything outside
///     SecurityConstants.allowedClockSkew (30s), so samples are bounded
///     by that, but a device with a badly-set clock will skew its own
///     samples. Treat single samples as indicative, aggregates as real.
///   * discovery and connection-establishment latency are owned by the
///     native layer (NearbyConnectionsManager) -- Dart only sees the
///     resulting PeerConnected event. Those two stages are recorded
///     natively and reported up through MeshChannelHandler's
///     "getRelayStats"; until that call succeeds they read as unmeasured
///     rather than zero.
///   * packet loss cannot be measured honestly from a single device --
///     a device does not know what it never received. `dropRate` below
///     is LOCAL drop rate (malformed/invalid/closed packets rejected by
///     this device), which is a different thing and is named as such.
///     True packet loss needs the multi-device harness.
class MeshMetrics {
  MeshMetrics._();
  static final instance = MeshMetrics._();

  int sent = 0;
  int received = 0;
  int relayed = 0;
  int uploaded = 0;
  int dropped = 0;

  final _controller = StreamController<void>.broadcast();

  /// Emits after any counter changes, so live UI can rebuild. Purely
  /// additive -- nothing that increments the counters is required to
  /// call this, but MeshService does so the relay screen stays fresh.
  Stream<void> get changes => _controller.stream;

  /// Call after mutating any counter to push a UI refresh.
  void notify() {
    if (!_controller.isClosed) _controller.add(null);
  }

  // ==========================================================
  // PRIORITY 1 -- latency instrumentation
  // ==========================================================

  /// Time spent verifying an Ed25519 signature. Measured around the
  /// `_signing.verify` call in MeshService._handlePayload -- this is the
  /// single most expensive CPU step in the receive path, so if relay
  /// latency regresses this is the first place to look.
  final LatencySamples signatureVerify = LatencySamples('signature_verify');

  /// Payload bytes arriving from native -> packet handed to the relay
  /// queue. Covers decode + validate + verify + dedup bookkeeping. This
  /// is the latency this device ITSELF adds to a multi-hop route.
  final LatencySamples receiveToRelay = LatencySamples('receive_to_relay');

  /// How long a packet sat in the priority relay queue before being
  /// handed to the transport. Non-zero here under load is exactly what
  /// the priority queue is supposed to prevent for CRITICAL traffic --
  /// compare `queueWaitByPriority` per tier, not just the aggregate.
  final LatencySamples queueWait = LatencySamples('queue_wait');

  /// Transport hand-off duration (MethodChannel round trip to native
  /// broadcastBytes). Does not include over-the-air time, which Nearby
  /// Connections does not expose.
  final LatencySamples relayDispatch = LatencySamples('relay_dispatch');

  /// Origin timestamp (packet.timestamp, set by the ORIGINATING device)
  /// -> successful backend upload on this device. The number that
  /// actually matters for "how long until a responder can see this SOS".
  /// Clock-skew caveat in the class doc applies.
  final LatencySamples endToEnd = LatencySamples('end_to_end');

  /// Backend upload call duration alone, so a slow network can be told
  /// apart from a slow mesh.
  final LatencySamples backendUpload = LatencySamples('backend_upload');

  /// Per-priority queue wait, so "critical packets never wait behind
  /// routine traffic" is a checkable claim and not an aspiration.
  final Map<String, LatencySamples> queueWaitByPriority = {};

  void recordQueueWait(String priorityName, Duration waited) {
    queueWait.add(waited);
    (queueWaitByPriority[priorityName] ??= LatencySamples('queue_wait_$priorityName'))
        .add(waited);
  }

  // ---------- relay / duplicate accounting ----------

  /// Relay attempts handed to the transport (whether or not the
  /// transport later succeeded -- Nearby Connections' sendPayload is
  /// fire-and-forget, see relaySuccessRate's caveat).
  int relayAttempts = 0;

  /// Relay attempts that threw before reaching the transport.
  int relayFailures = 0;

  /// Relays this device deliberately suppressed because a neighbouring
  /// peer had already propagated the same packet (duplicate-storm
  /// protection, PRIORITY 4). Suppression is a SUCCESS, not a failure --
  /// counted separately so it can never be mistaken for packet loss.
  int relaySuppressed = 0;

  /// Duplicates rejected by the native seen-cache before they ever
  /// reached Dart. Populated from the native relay stats, so it stays 0
  /// until the first successful `getRelayStats` call.
  int duplicatesFiltered = 0;

  /// Total payloads the native engine looked at (unique + duplicate).
  /// Denominator for duplicateRate.
  int nativeTotalProcessed = 0;

  /// Native-side discovery/connection timings, in microseconds, pulled
  /// up from NearbyConnectionsManager. `null` means not measured yet --
  /// deliberately nullable so an unmeasured stage can never be reported
  /// as "0 ms".
  int? discoveryLatencyMicros;
  int? connectionLatencyMicros;

  /// Fraction of everything the native engine saw that was a duplicate.
  /// High is not automatically bad in a dense mesh -- it means flooding
  /// is reaching devices from several directions -- but a sharp rise
  /// after a change means the storm protection regressed.
  double? get duplicateRate =>
      nativeTotalProcessed == 0 ? null : duplicatesFiltered / nativeTotalProcessed;

  /// Attempts that reached the transport without throwing.
  ///
  /// CAVEAT, stated so nobody quotes this as delivery confirmation:
  /// Nearby Connections' sendPayload does not report per-peer delivery
  /// back to us, so this measures "we successfully handed it to the
  /// radio", NOT "a peer received it". Real delivery confirmation comes
  /// from AckPacket, and from the multi-device harness.
  double? get relaySuccessRate =>
      relayAttempts == 0 ? null : (relayAttempts - relayFailures) / relayAttempts;

  /// Local drop rate -- packets THIS device rejected (malformed,
  /// bad signature, expired TTL, closed emergency) over everything it
  /// received. Not packet loss; see class doc.
  double? get localDropRate {
    final seenHere = received + dropped;
    return seenHere == 0 ? null : dropped / seenHere;
  }

  // ---------- battery ----------

  /// Battery level when instrumentation first saw traffic, and the most
  /// recent reading. Delta is only meaningful over a long session with a
  /// known workload -- recorded, but not presented as "battery cost per
  /// packet", which this cannot honestly support.
  int? batteryAtFirstSample;
  int? batteryLatest;
  DateTime? batteryFirstSampleAt;

  void recordBattery(int level) {
    batteryLatest = level;
    if (batteryAtFirstSample == null) {
      batteryAtFirstSample = level;
      batteryFirstSampleAt = DateTime.now();
    }
  }

  /// Percentage points consumed since the first sample. Positive = drain.
  int? get batteryDelta => (batteryAtFirstSample == null || batteryLatest == null)
      ? null
      : batteryAtFirstSample! - batteryLatest!;

  Duration? get batteryObservationWindow => batteryFirstSampleAt == null
      ? null
      : DateTime.now().difference(batteryFirstSampleAt!);

  /// Merges a stats map pushed up from the native relay engine.
  /// Tolerant of missing keys so a native build without the newer
  /// `getRelayStats` method degrades to "unmeasured", never to wrong
  /// numbers.
  void applyNativeStats(Map<dynamic, dynamic> stats) {
    final processed = stats['totalProcessed'];
    final dupes = stats['duplicatesFiltered'];
    final suppressed = stats['relaySuppressed'];
    final discovery = stats['discoveryLatencyMicros'];
    final connection = stats['connectionLatencyMicros'];

    if (processed is int) nativeTotalProcessed = processed;
    if (dupes is int) duplicatesFiltered = dupes;
    if (suppressed is int) relaySuppressed = suppressed;
    if (discovery is int && discovery > 0) discoveryLatencyMicros = discovery;
    if (connection is int && connection > 0) connectionLatencyMicros = connection;
    notify();
  }

  /// Machine-readable snapshot for tests and debug reporting. Every
  /// unmeasured value is `null`, never 0 -- a test asserting on this map
  /// can therefore distinguish "measured as zero" from "never measured",
  /// which is the whole point.
  Map<String, dynamic> snapshot() => {
        'counters': {
          'sent': sent,
          'received': received,
          'relayed': relayed,
          'uploaded': uploaded,
          'dropped': dropped,
          'relayAttempts': relayAttempts,
          'relayFailures': relayFailures,
          'relaySuppressed': relaySuppressed,
          'duplicatesFiltered': duplicatesFiltered,
          'nativeTotalProcessed': nativeTotalProcessed,
        },
        'rates': {
          'duplicateRate': duplicateRate,
          'relaySuccessRate': relaySuccessRate,
          'localDropRate': localDropRate,
        },
        'latencyMicros': {
          'signatureVerify': signatureVerify.snapshot(),
          'receiveToRelay': receiveToRelay.snapshot(),
          'queueWait': queueWait.snapshot(),
          'relayDispatch': relayDispatch.snapshot(),
          'endToEnd': endToEnd.snapshot(),
          'backendUpload': backendUpload.snapshot(),
          'queueWaitByPriority': {
            for (final entry in queueWaitByPriority.entries)
              entry.key: entry.value.snapshot(),
          },
          'discovery': discoveryLatencyMicros,
          'connectionEstablish': connectionLatencyMicros,
        },
        'battery': {
          'firstSample': batteryAtFirstSample,
          'latest': batteryLatest,
          'deltaPercent': batteryDelta,
          'observationWindowSeconds': batteryObservationWindow?.inSeconds,
        },
      };

  void log() {
    developer.log(
      '''
Mesh Metrics
Sent      : $sent
Received  : $received
Relayed   : $relayed
Uploaded  : $uploaded
Dropped   : $dropped
''',
      name: 'MeshMetrics',
    );
  }

  /// Human-readable performance report. Used by the debug metrics screen
  /// and when recording benchmark runs into docs/MESH_PERFORMANCE.md --
  /// anything it prints as "not measured" must NOT be given a number in
  /// that document.
  String report() {
    final buffer = StringBuffer()
      ..writeln('=== SETU Mesh Performance ===')
      ..writeln('sent=$sent received=$received relayed=$relayed '
          'uploaded=$uploaded dropped=$dropped')
      ..writeln('relayAttempts=$relayAttempts failures=$relayFailures '
          'suppressed=$relaySuppressed')
      ..writeln('duplicateRate=${_pct(duplicateRate)} '
          'relaySuccessRate=${_pct(relaySuccessRate)} '
          'localDropRate=${_pct(localDropRate)}')
      ..writeln(signatureVerify)
      ..writeln(receiveToRelay)
      ..writeln(queueWait);
    for (final entry in queueWaitByPriority.entries) {
      buffer.writeln('  ${entry.value}');
    }
    buffer
      ..writeln(relayDispatch)
      ..writeln(backendUpload)
      ..writeln(endToEnd)
      ..writeln('discovery: ${_ms(discoveryLatencyMicros)}')
      ..writeln('connectionEstablish: ${_ms(connectionLatencyMicros)}')
      ..writeln('battery: ${batteryDelta == null ? 'not measured' : '$batteryDelta%'} '
          'over ${batteryObservationWindow?.inSeconds ?? '-'}s');
    return buffer.toString();
  }

  static String _pct(double? value) =>
      value == null ? 'not measured' : '${(value * 100).toStringAsFixed(1)}%';

  static String _ms(int? micros) =>
      micros == null ? 'not measured' : '${(micros / 1000).toStringAsFixed(1)}ms';

  void reset() {
    sent = 0;
    received = 0;
    relayed = 0;
    uploaded = 0;
    dropped = 0;
    relayAttempts = 0;
    relayFailures = 0;
    relaySuppressed = 0;
    duplicatesFiltered = 0;
    nativeTotalProcessed = 0;
    discoveryLatencyMicros = null;
    connectionLatencyMicros = null;
    batteryAtFirstSample = null;
    batteryLatest = null;
    batteryFirstSampleAt = null;
    signatureVerify.reset();
    receiveToRelay.reset();
    queueWait.reset();
    relayDispatch.reset();
    endToEnd.reset();
    backendUpload.reset();
    queueWaitByPriority.clear();
    notify();
  }
}

/// Fixed-cost latency accumulator.
///
/// Keeps a running count/sum/min/max (O(1), no allocation) plus a bounded
/// ring of the most recent [_ringSize] samples so a median and p95 can be
/// reported without retaining every sample for the life of the process.
/// Percentiles are therefore over the RECENT window, not all time -- which
/// is what you want when checking whether a change just made things worse.
class LatencySamples {
  LatencySamples(this.name);

  final String name;
  static const int _ringSize = 128;

  final List<int> _ring = <int>[];
  int _ringCursor = 0;

  int count = 0;
  int totalMicros = 0;
  int minMicros = 0;
  int maxMicros = 0;

  void add(Duration duration) => addMicros(duration.inMicroseconds);

  void addMicros(int micros) {
    // A negative sample means the two clocks involved disagree (see the
    // end-to-end caveat in MeshMetrics). Recording it would drag the
    // average down and make the mesh look faster than it is, so it is
    // discarded rather than clamped to zero.
    if (micros < 0) return;

    if (count == 0) {
      minMicros = micros;
      maxMicros = micros;
    } else {
      if (micros < minMicros) minMicros = micros;
      if (micros > maxMicros) maxMicros = micros;
    }
    count++;
    totalMicros += micros;

    if (_ring.length < _ringSize) {
      _ring.add(micros);
    } else {
      _ring[_ringCursor] = micros;
      _ringCursor = (_ringCursor + 1) % _ringSize;
    }
  }

  /// Convenience for the common `final sw = Stopwatch()..start(); ...`
  /// pattern, so call sites stay one line.
  Future<T> time<T>(Future<T> Function() action) async {
    final stopwatch = Stopwatch()..start();
    try {
      return await action();
    } finally {
      stopwatch.stop();
      addMicros(stopwatch.elapsedMicroseconds);
    }
  }

  double? get averageMicros => count == 0 ? null : totalMicros / count;

  int? percentileMicros(double fraction) {
    if (_ring.isEmpty) return null;
    final sorted = List<int>.from(_ring)..sort();
    final index = (sorted.length * fraction).floor().clamp(0, sorted.length - 1);
    return sorted[index];
  }

  int? get medianMicros => percentileMicros(0.5);
  int? get p95Micros => percentileMicros(0.95);

  Map<String, dynamic> snapshot() => {
        'count': count,
        'avg': averageMicros,
        'min': count == 0 ? null : minMicros,
        'max': count == 0 ? null : maxMicros,
        'median': medianMicros,
        'p95': p95Micros,
      };

  void reset() {
    _ring.clear();
    _ringCursor = 0;
    count = 0;
    totalMicros = 0;
    minMicros = 0;
    maxMicros = 0;
  }

  @override
  String toString() {
    if (count == 0) return '$name: not measured';
    String ms(num? micros) =>
        micros == null ? '-' : '${(micros / 1000).toStringAsFixed(1)}ms';
    return '$name: n=$count avg=${ms(averageMicros)} '
        'median=${ms(medianMicros)} p95=${ms(p95Micros)} '
        'min=${ms(minMicros)} max=${ms(maxMicros)}';
  }
}
