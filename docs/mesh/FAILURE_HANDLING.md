# SETU Mesh — Failure Handling

Owner: Vib (Mesh/Architecture). Source-level audit as of Sep 21 2026,
covering connection lifecycle, store-and-forward, battery-aware relay,
exit-node behavior, and general failure scenarios.

## Connection Lifecycle

Discovery, connect, disconnect, and advertising are entirely **native**
(Android Kotlin) — Dart only observes `PeerConnected` / `PeerDisconnected`
/ `PayloadReceived` events over an EventChannel. A disconnected peer is
simply removed from the tracked cluster set; nothing in the relay path
blocks on a specific peer, so queued packets keep draining to whoever is
still connected — this satisfies "a failed node must not block the
pipeline."

**Resolved (Bulk Sprint 2, native audit pass)** — this was previously flagged
as unverified because it lives entirely in native Kotlin, which was out of
Sprint 1's file scope. It has now been directly audited: a lexicographic
tie-break (`localEndpointName < info.endpointName` in
`NearbyConnectionsManager.onEndpointFound`) correctly decides which device
calls `requestConnection` vs. waits to `acceptConnection`, with an explicit
in-code comment describing exactly the failure mode it fixes. **Confirmed
correct, not broken.** One real gap found alongside it and fixed this pass:
nothing previously guarded against re-requesting a connection to an
endpoint already present in `connectedEndpoints` — duty-cycling stops and
restarts discovery every burst while a connection persists, so Nearby
Connections re-firing `onEndpointFound` for an already-connected peer was a
reachable case, not hypothetical. See `NATIVE_MESH_AUDIT.md` §2 and §12.

**Also confirmed this pass**: connection acceptance (`onConnectionInitiated`)
auto-accepts every incoming connection unconditionally, with no
authentication/token check on the peer. Not fixed — this is a real feature
addition with UX implications (some form of peer trust/pairing), not a
mechanical patch. See `NATIVE_MESH_AUDIT.md` §3.

**CONFIRMED, but in dead code — not fixed, documented instead**:
`lib/screens/home/home_screen.dart` constructs its own independent
`MeshServiceImpl` (separate `NearbyService`/`BackendService`/
`LocalQueueService` instances) in `initState()`. If this screen were
reachable, having two live `MeshServiceImpl` instances both subscribed to
the same native event stream would mean double signature verification,
double relay dispatch, and double backend-submission attempts for every
packet while both were alive. **However**, `lib/routes/app_router.dart`
routes `HomeScreen` from `lib/features/home/presentation/screens/home_screen.dart`
— a different, unrelated file — and grep across `lib/` and `test/` found
**no import of `screens/home/home_screen.dart` anywhere**. This file is
orphaned/dead code, not reachable from the actual app navigation. Not
edited this pass: fixing a bug inside genuinely unreachable code adds no
runtime safety value, and deleting it is a separate decision (something
else might reference it in a way this audit's grep missed, or it might be
intentionally kept as a reference/debug screen) that the mesh-hardening
brief did not ask for. **Recommend the team explicitly decide to delete
or wire it up — leaving it as silently-dead code with a live bug inside it
is the worst of both options.**

`MeshServiceImpl.dispose()` — minor gap fixed this pass:
`_incomingController` (a `StreamController`) was never `.close()`d, unlike
`_acknowledgmentsController` which was. No functional impact (a broadcast
controller with no listeners is cheap), but the asymmetry had no reason
behind it. Now closed alongside the other controller.

## Store-and-Forward

Durable queue is SQLite-backed (`LocalQueueService`), primary-keyed on
`packetId`, `ConflictAlgorithm.ignore` on insert — re-enqueuing an already-
stored packet is a safe no-op, confirmed correct.

**Fixed this pass — unbounded retry, no ack on retry-only delivery**:
- `_retryPendingUploads()` (30-second timer) previously re-uploaded every
  still-pending row forever, with no backoff and no attempt cap.
  `MeshConstants.maxRetryAttempts` and the entire `RetryPolicy`/
  `UploadScheduler` exponential-backoff classes exist in the codebase but
  were **never instantiated anywhere** — dead code suggesting backoff was
  planned but never wired in. **Not wired in this pass either** — a flat
  30-second retry with no cap is arguably the *correct* choice for
  emergency traffic (an undelivered SOS should keep trying, not give up
  after N attempts), so this was left as-is rather than "fixed" by adding
  an arbitrary cap that could cause a real emergency packet to stop
  retrying. Flagged for a deliberate product decision, not silently
  patched.
- A packet delivered only via the retry path (not the immediate
  `_tryUpload`) never originated an ack back to the sender — **fixed**,
  see `ACK_LIFECYCLE.md`.
- A race allowing the same packet to be uploaded twice if the retry timer
  fired while an immediate upload was still in flight — **fixed** via a
  client-side in-flight guard (`_uploadingPacketIds`), see
  `ACK_LIFECYCLE.md`.

**Fixed this pass — queue growth**: `LocalQueueService.pruneUploaded()`
(deletes already-uploaded rows older than 3 days) existed but was **never
called from anywhere** in `lib/`. Now called every 5 minutes alongside the
existing responder-registry sync timer. Never touches rows still pending
upload.

**Not fixed / not found broken**: no evidence of corrupted-record handling
gaps — `getPendingPackets()` already wraps each row's JSON decode in a
`try/catch` and skips malformed rows rather than crashing the whole queue
read.

## Battery-Aware Relay

Actual thresholds in code (`BatteryService._updateMode`):
**>50% → full power, 20–50% → balanced, <20% → power saver.**

`MeshPolicy.fromPowerMode`: power-saver mode sets `allowRelay: false`,
`allowUpload: false`. Full/balanced both allow relay+upload, differing
only in scan/discovery/retry intervals.

**Confirmed correct**: low battery skips relaying *other devices'*
traffic, but never blocks the device's *own* originated emergency packet
— `originate()` sends directly and never consults `_currentPolicy.allowRelay`
at all (explicitly documented in the source: "Self-originated traffic
bypasses the priority queue entirely").

**Gap found, not fixed this pass**: power-saver's `allowUpload: false` is
checked in the relay-decision path (for packets being relayed on behalf of
others) but **`_tryUpload()`, called directly from a device's own
`originate()`, is not gated by `allowUpload` at all** — so a device in
power-saver mode will still attempt to upload its *own* originated SOS if
it happens to have internet. This is almost certainly the *correct*
behavior (an emergency originator's own traffic should never be blocked by
its own low battery) but it is inconsistent with how `allowUpload` is
documented/enforced elsewhere, and nothing in the code states this is
deliberate. **Not changed this pass** — changing upload-gating behavior
for a device's own SOS is exactly the kind of decision that needs product
sign-off, not a source-level guess. Flagged for Ayush/team discussion.

Exit-node behavior itself has no separate battery gate beyond the generic
`allowRelay`/`allowUpload` flags above.

## Exit-Node Logic

No explicit "exit node" state exists — any device with internet at the
moment `hasRealInternet()` is checked opportunistically uploads. This is a
simple, robust design; **fixed this pass**: the double-submission race
described in Store-and-Forward above (same underlying mechanism, since
"exit node" and "upload" are the same code path in this architecture).

## Failure Scenarios Reviewed

| Scenario | Expected | Actual (source-verified) | Gap | Fix this pass |
|---|---|---|---|---|
| Backend unavailable | Packet stays queued, retried later | `_tryUpload`/`_retryPendingUploads` both simply skip on `!online` or a failed `uploadPacket` call, packet stays `uploaded=0` | None found | — |
| Malformed/corrupt payload received | Dropped, no crash | Wrapped in `try/catch` in `_handlePayload`, logged and dropped | None found | — |
| Oversized payload | Should be rejected cheaply | **Was not enforced at all** — `SecurityConstants.maxPacketSize` was declared but never checked | Real gap | **Fixed**: byte-length check added at the very top of `_handlePayload`, before JSON decode |
| Relay dispatch fails (transport error) | Must not block the queue pump | `_dispatchRelay` catches the error, logs, continues the loop | None found | — |
| Same packet uploaded twice concurrently | Should not happen client-side | Was possible (see Store-and-Forward) | Real gap | **Fixed** |
| Packet delivered only via retry | Sender should still get an ack | Was not happening (see ACK_LIFECYCLE.md) | Real gap | **Fixed** |
| App restart with pending queue | Queue survives, retry resumes | SQLite-backed, persists across restart by construction; `_retryPendingUploads()` is also called once immediately in the constructor | None found | — |
| Emergency terminated (TerminationPacket) | Stop relaying/uploading for that emergency | Durable queue AND in-memory relay queue are both swept (`markEmergencyClosed` + `_relayQueue.removeEmergency`) | None found | — |
| Registry not yet synced, termination received | Documented fail-open (MVP gap, not a bug) | `ResponderRegistry.checkResponder` returns `(true, false)` when no registry has synced, i.e. an unauthenticated termination is currently accepted before first backend sync | Known, pre-existing, documented in source already | Not addressed this pass — this is a policy/security decision (accept-unverified-until-first-sync vs. reject-until-verified), not something to silently change |
| Foreground service killed and restarted (`START_STICKY`) | Relay/dedup state should survive, or at least not misbehave | Native `PacketRelayEngine` rebuilt fresh (empty `seen` cache) and `currentAllowRelay`/`currentDiscoveryIntervalMs` reset to full-power defaults until Dart re-syncs via `updateMeshPolicy` | Real gap (native audit, Bulk Sprint 2) | Not fixed — persisting policy/location across process death is a scoped feature addition (e.g. SharedPreferences), not a one-line patch. See `NATIVE_MESH_AUDIT.md` §16 |
| Concurrent native callback delivery (dedup cache / connection set touched from multiple Nearby Connections threads) | Read-check-write sequences must be atomic | Previously unsynchronized (`PacketRelayEngine`'s `seen`/counters, `NearbyConnectionsManager`'s `connectedEndpoints`/`connectionStartedAtNanos`) | Real gap (native audit, Bulk Sprint 2) | **Fixed** — wrapped in `synchronized(lock)` / `Collections.synchronized*` + explicit iteration locking in `broadcastBytes()`. See `NATIVE_MESH_AUDIT.md` §17 |
| Bluetooth/Wi-Fi toggled off then back on while service is running | Advertising/discovery should resume automatically | Previously: silently stayed inactive until the app/service was manually restarted -- no listener for radio state changes existed | Real gap (Bulk Sprint 3) | **Fixed** — `MeshForegroundService` now registers a `BroadcastReceiver` for `BluetoothAdapter.ACTION_STATE_CHANGED` and Wi-Fi's `WIFI_STATE_CHANGED` and calls the existing `startDutyCycle()` on a transition to ON. No new permissions needed (both already declared). Not validated on real hardware. |
| Flapping Nearby connection (repeated failed connection attempts to the same endpoint) | Should back off, not hammer the same endpoint immediately | Previously: no backoff at all -- a failed `requestConnection` could be retried on every discovery burst with no delay | Real gap (Bulk Sprint 3) | **Fixed for the connection-attempt-failure case only** — bounded exponential backoff (2s initial, doubling, 30s ceiling, reset on success) in `NearbyConnectionsManager`. Deliberately does NOT cover a connection that succeeds then disconnects quickly (see `NATIVE_FAILURE_MATRIX.md` row 7) -- no real-device data to pick a duration threshold from. Backoff values themselves not validated on real hardware. |
| Foreground service killed and restarted, dedup cache / battery policy amnesia (see row above) | Should restore last-known state, not reset to defaults | Previously: full reset to hardcoded defaults every restart | Real gap (Bulk Sprint 2, addressed Bulk Sprint 3) | **Fixed** — `MeshStateStore` (SharedPreferences) persists the current policy on every explicit change and a bounded snapshot of the dedup cache on a 30s timer + best-effort on `onDestroy()`. `onCreate()` restores both before starting discovery. An abrupt OOM-kill (no `onDestroy()` guarantee) can still lose up to one persistence interval's worth of dedup history -- accepted, documented trade-off, not a correctness bug (still bounded by TTL and every other device's own dedup). See `MeshStateStore.kt`'s doc comment for the full reasoning. |
