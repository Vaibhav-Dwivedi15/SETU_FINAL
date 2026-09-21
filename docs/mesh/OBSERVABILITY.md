# SETU Mesh — Observability

Owner: Vib (Mesh/Architecture). Source-level audit as of Sep 21 2026.

## Current Implementation

`MeshMetrics` (singleton, `lib/mesh/services/mesh_metrics.dart`) already
tracks a substantial set of counters and timing samples: `sent`,
`received`, `relayed`, `relayFailures`, `dropped`, `uploaded`, latency
histograms for `relayDispatch`, `signatureVerify`, `receiveToRelay`,
`backendUpload`, `endToEnd`, plus per-priority queue-wait recording and a
battery-level sample on every send/receive. It also pulls native-side
duplicate-suppression and discovery/connection timing stats once a minute
via `_pullNativeStats()` (read-only, explicitly documented as must-not-
become-a-load-source).

`RelayLogRepository` persists a human-readable event log (sent / received
/ relayed / dropped / uploaded, each with a reason string) — this is what
actually answers "what happened to packet X" after the fact, since
`MeshMetrics` is just counters, not a per-packet history.

## Changes This Pass

The new size-guard, upload-race-guard, and retry-ack-fix all log through
the **existing** `RelayLogRepository`/`developer.log` mechanisms rather
than introducing a new logging framework — consistent with the sprint
brief's instruction to extend an existing event layer rather than build a
new one:
- Oversized payload drop → `RelayLogType.dropped`, detail includes byte count.
- Skipped concurrent upload → `developer.log` only (not persisted to
  `RelayLogRepository` — this is an internal race-avoidance detail, not a
  user-meaningful mesh event like a genuine drop; logging it to the
  persistent, user-visible relay log would be noise).
- Retry-path delivery now logs `'Delivered to backend (retry)'` exactly as
  before (unchanged), now additionally followed by an ack origination log
  line from `_originateAck`.

## Not Done This Pass

A full "structured mesh event model" (`PACKET_CREATED`, `ACK_MATCHED`,
`ACK_UNKNOWN`, etc. as an enum-typed event stream) was **not built**. The
existing `RelayLogRepository` + `MeshMetrics` combination already covers
the practical needs (a persistent per-packet log for debugging, plus
aggregate counters/timings for dashboards), and per the sprint brief's own
instruction not to build "a giant framework" when a suitable layer already
exists, adding a second, parallel event-typing system this pass would be
scope creep without a concrete consumer asking for it. If a future need
appears (e.g. exporting structured events to the backend for cross-device
correlation), that is a real design task, not a mechanical addition.

## Native Layer (Bulk Sprint 2)

`_pullNativeStats()` reads native counters (`totalProcessed`,
`duplicatesFiltered`, `relaySuppressed`) that were previously `@Volatile`
but incremented with a non-atomic `++` — under concurrent callback
delivery this could under-count (a classic lost-update race, not a crash).
**Fixed this pass**: `noteSuppressedRelay()` and the counter increments
inside `process()` now run inside the same `synchronized(lock)` block as
the dedup check itself, so the counts `_pullNativeStats()` reads are now
exact, not approximate. `discoveryLatencyMicros`/`connectionLatencyMicros`
(read by the same stats pull) have a benign check-then-set race that was
**not** fixed — worst case is an occasional slightly-stale latency sample,
never a wrong value that persists, and fixing it would add synchronization
overhead to a one-shot "time to first peer" measurement for no real
accuracy gain. See `NATIVE_MESH_AUDIT.md` §17.

## Logging Hygiene Check

Grepped all mesh-layer `developer.log`/`RelayLogRepository.log` calls
touched or newly added this pass for private keys, API keys, passwords,
medical/personal data — none found. Existing logs already truncate
`senderId` to its first 8 characters in log lines (e.g.
`sender=${packet.senderId.substring(0, 8)}...`), which was not changed.
