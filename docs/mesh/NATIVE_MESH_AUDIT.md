# SETU Native (Kotlin) Mesh Layer — Audit

Owner: Vib. Source-level audit as of Sep 21 2026, covering
`MeshForegroundService.kt`, `NearbyConnectionsManager.kt`,
`PacketRelayEngine.kt`, `MainActivity.kt`, and the MethodChannel handlers
under `com.setu.setu_app.handlers`.

**Important correction to the previous (Dart-only) hardening report**: that
report speculated the native layer might be "purely a dumb transport."
This audit confirms that is **wrong** — the native layer independently
implements its own dedup, TTL, and relay-decision logic in
`PacketRelayEngine`, entirely separate from (and running even when) the
Dart layer is not attached. Native is a full second implementation of
relay-critical logic, not a passthrough. This matters for every other doc
in this folder — see the "Correction" notes added to `DEDUPLICATION.md`
and `TTL.md`.

For each area: CURRENT CODE / EXPECTED BEHAVIOR / ACTUAL BEHAVIOR / RISK / ACTION.

## 1. Discovery Lifecycle

- **Current code**: `NearbyConnectionsManager.startAdvertising()`/`startDiscovery()`, both using `Strategy.P2P_CLUSTER`. Called together from `MeshForegroundService.startDutyCycle()`.
- **Expected**: device should advertise+discover on a battery-appropriate duty cycle.
- **Actual**: duty-cycling exists — bursts on 5s then off for the rest of the configured interval, driven by `Handler(Looper.getMainLooper())`. Full-power tier (`discoveryIntervalMs <= 5000`) just runs continuously to avoid a `STATUS_ALREADY_ADVERTISING` crash from double-starting.
- **Risk**: during an "off" window, a bystander device is genuinely undiscoverable (up to ~25s in power-saver) — disclosed as an accepted trade-off in the existing code comments, not a bug.
- **Action**: none. Confirmed correct as designed.

## 2. Connection Request Lifecycle

- **Current code**: `onEndpointFound` — lexicographic compare (`localEndpointName < info.endpointName`) decides who calls `requestConnection`; the loser waits to `acceptConnection`.
- **Expected**: deterministic tie-break so simultaneous mutual discovery doesn't drop both requests.
- **Actual**: present and correct, with an explicit code comment describing exactly the failure mode it fixes ("endpoints found, then Lost endpoint, no connection ever completing").
- **Risk (fixed this pass)**: no guard existed against re-requesting an endpoint already in `connectedEndpoints` — duty-cycling stops/restarts discovery every burst while a connection persists, so a re-fired `onEndpointFound` for an already-connected peer was a real, reachable case.
- **Action**: **FIXED** — added an early-return guard in `onEndpointFound` when `connectedEndpoints.contains(endpointId)`.

## 3. Connection Acceptance

- **Current code**: `onConnectionInitiated` auto-accepts every incoming connection unconditionally, no check on `info` (which carries an auth token in the real Nearby Connections API).
- **Expected**: some basis for deciding to accept, ideally tied to the app's own trust model.
- **Actual**: blind auto-accept — any endpoint offering the correct `serviceId` connects.
- **Risk**: an attacker-controlled device with the app installed (or a compatible client) can connect freely; this is somewhat mitigated by signature verification happening one layer up (Dart), so an unauthenticated *connection* doesn't equal an unauthenticated *packet* — but see §5 (native relay/rebroadcast decisions happen with ZERO signature check, purely on packet_id + ttl).
- **Action**: **not fixed this pass.** Adding real peer authentication (e.g. requiring Nearby Connections' auth-token confirmation UX, or an app-level pairing step) is a real feature with UX implications, not a "smallest safe fix." Documented as a known gap for a deliberate security/product decision.

## 4. Payload Receive Lifecycle

- **Current code**: `NearbyConnectionsManager.payloadCallback.onPayloadReceived` → `MeshForegroundService.onPayloadReceived` → `PacketRelayEngine.process(bytes, lat, lon)`.
- **Expected**: dedup, decide relay, notify Dart.
- **Actual**: exactly that, entirely in Kotlin — `process()` parses JSON, checks `seen` (dedup), computes new TTL via `nextTtl()`, and returns relay bytes directly usable by `broadcastBytes()`. Dart is notified in parallel via `eventForwarder` purely for UI/backend-upload, **not** as part of the relay critical path.
- **Risk (fixed this pass)**: `process()`'s internal state (`seen`, `seenAtLocation`, `echoTimestamps`, counters) was not thread-safe against concurrent callback delivery.
- **Action**: **FIXED** — the whole `process()` body (and `rememberOriginated()`, `recentEchoCount()`) now runs inside `synchronized(lock)`, making the dedup check-and-record sequence atomic, not just individual map operations.

## 5. Signature Verification

- **Current code**: none in Kotlin. Grepped all 8 audited files — no crypto/Signature imports anywhere.
- **Expected**: relay of a packet should ideally require the packet to at least look genuine.
- **Actual**: `PacketRelayEngine` trusts `packet_id`/`priority`/`ttl`/`timestamp`/`hop_count` fields from raw JSON with zero authenticity check. Real signature verification is Dart-side only (`SigningService.verify` in `mesh_service.dart`).
- **Risk**: while the app is backgrounded and only the native foreground service is running (a real, common state for this app), native will relay and rebroadcast **any well-formed JSON blob** claiming those fields — no signature gate exists at that layer.
- **Action**: **not fixed this pass.** Porting Ed25519 verification into Kotlin is a substantial addition (crypto library, key format handling, a second implementation to keep in sync with the Dart one) — explicitly outside "smallest safe fix" territory and outside this sprint's non-negotiable rule against modifying crypto without a concrete, scoped decision. Documented as the top security-relevant native gap.

## 6. Deduplication

See `DEDUPLICATION.md` (updated this pass) for full detail. Summary: `seen` is a `LinkedHashSet<String>` keyed on `packet_id`, bounded at 500, FIFO-evicted. Insertion happens before any TTL/signature check (there is no signature check to order against). Thread-safety fixed this pass (§4).

## 7. TTL Handling

See `TTL.md` (updated this pass). Native has its own real `nextTtl()`, a hand-maintained mirror of Dart's `AdaptiveTtl.nextTtl` — same invariants (result ≤ MAX_TTL, result < input, result ≥ 0), same stale-packet extra-decrement rule. `MAX_TTL = 5` is a separately-declared Kotlin constant with a comment saying it "must stay in sync with SecurityConstants.maxTTL (Dart)" — **no compile-time or runtime enforcement of that sync**, a real (if narrow) drift risk flagged but not fixed this pass (see §22).

## 8. Relay Decision

`process()` returns a `RelayResult` with `relayBytes` already computed (new TTL, incremented hop count) whenever relay is warranted; `MeshForegroundService` applies jitter + echo-suppression before actually calling `broadcastBytes()`. TTL is genuinely checked and decremented in Kotlin, not deferred to Dart.

## 9. ACK Generation

**None in Kotlin.** No ack/acknowledgement construction exists in any audited native file. `_originateAck()` is Dart-only (`mesh_service.dart`). Native only moves bytes for whatever packet type Dart or another peer already originated — it never manufactures a new packet type of its own.

## 10. ACK Forwarding

An `AckPacket`'s bytes are just another payload to `PacketRelayEngine.process()` — no special-cased handling exists (or is needed) in Kotlin; it is deduped and relayed exactly like any other packet type, consistent with the Dart-side design documented in `ACK_LIFECYCLE.md` (an ack is not a privileged packet).

## 11. Disconnect Handling

`onDisconnected` removes the endpoint from `connectedEndpoints` and `connectionStartedAtNanos`, logs, and notifies the listener. Confirmed correct — no leak found in this path specifically.

## 12. Rediscovery

Previously unguarded against re-requesting an already-connected endpoint — see §2 (fixed). No backoff/cooldown exists for a flapping connection (rapid connect/disconnect, e.g. marginal BLE range); nothing throttles reconnection attempts. **Not fixed this pass** — a real fix here (exponential backoff per endpoint) is more than a one-line guard and risks changing reconnection behavior in ways that need testing against real hardware this sandbox doesn't have. Documented as a known gap.

## 13. Store-and-Forward

Native has no durable persistence of its own — `LocalQueueService` (SQLite) is entirely Dart-side. Native's only "memory" of a packet is the in-process `seen` cache, which does not survive a process restart (see §14). This is a reasonable division: native's job is moving bytes reliably while alive, not durable storage.

## 14. Battery Behavior

Confirmed: **zero battery-level checks in Kotlin.** Battery policy is computed entirely in Dart (`PowerModeController`/`MeshPolicy`) and pushed to native via the `updateMeshPolicy` MethodChannel call, which native stores as `currentAllowRelay`/`currentDiscoveryIntervalMs` and applies at both duty-cycle timing and relay-gating (checked at receive AND again at dispatch time after jitter — a good defensive detail). On a `START_STICKY` process restart, these reset to hardcoded full-power defaults until Dart re-syncs — see §16.

## 15. Exit-Node Behavior

Not a native concept at all — "exit node" is purely "this device currently has internet," which is entirely a Dart-side (`BackendService.hasRealInternet()`) decision. Native has no awareness of connectivity state beyond what Dart tells it via the same policy channel as battery.

## 16. Foreground Service Lifecycle (additional finding, not in the original 15-item list but load-bearing)

- **Current code**: `onStartCommand` returns `START_STICKY`. On a system-triggered restart after being killed, `onCreate()` re-runs fully — rebuilds `PacketRelayEngine` (fresh, empty `seen` cache), resets `lastKnownLat/Lon` to null, and resets `currentAllowRelay`/`currentDiscoveryIntervalMs` to hardcoded defaults until Dart re-sends `updateMeshPolicy`.
- **Risk**: a restarted service briefly (a) has amnesia about what it's already relayed (dedup cache wiped — could re-relay something it already forwarded before the restart, though this is bounded by the same TTL/loop protections as any duplicate), and (b) runs at full power ignoring whatever battery tier was in effect, until Dart reconnects and re-syncs.
- **Action**: **not fixed this pass.** Persisting last-known policy/location across process death (e.g. via SharedPreferences) is a real, scoped feature addition, not a one-line fix — documented for a future pass.

## 17. Thread Safety — Summary

Full inventory and fixes in `THREAD_SAFETY` section of `FAILURE_HANDLING.md` (updated this pass). Fixed: `PacketRelayEngine`'s three collections + three counters (synchronized on a single lock covering the whole read-check-write sequence), `NearbyConnectionsManager`'s `connectedEndpoints`/`connectionStartedAtNanos` (synchronized collections + explicit iteration lock in `broadcastBytes`). Not fixed / low-risk and left as-is: `discoveryLatencyMicros`/`connectionLatencyMicros`'s check-then-set pattern (benign race, worst case a slightly-off latency sample, not a correctness issue); `pendingRelayIds` in `MeshForegroundService` (in practice serialized via a single `Handler(Looper.getMainLooper())`, so not independently synchronized this pass — flagged as relying on that implicit guarantee rather than an explicit one).

## 18. Existing Test Infrastructure

**None.** No `test/` or `androidTest/` directory under `android/app/src/`. Zero `*Test*.kt` files anywhere. `build.gradle.kts` declares no test dependencies (junit/espresso/mockk/robolectric). See `docs/mesh/MULTI_DEVICE_TEST_PLAN.md` for what a real test strategy would need, and the "Automated Tests" section of the final report for why none were added this pass.
