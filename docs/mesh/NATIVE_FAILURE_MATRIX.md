# SETU Native Mesh — Failure Matrix

Owner: Vib (Mesh/Architecture). Source-level audit as of Sep 21 2026,
covering the native Android Kotlin mesh layer only (`MeshForegroundService`,
`NearbyConnectionsManager`, `PacketRelayEngine`). Companion to
`FAILURE_HANDLING.md` (Dart-layer failure scenarios) — this table only
covers inputs/conditions whose handling actually lives in native code.

None of these rows are simulated or invented from guesswork; each is
traced to the actual code path in the audited files
(`NATIVE_MESH_AUDIT.md` has the file:line detail per row). Where a row
says "not verifiable from source," that means the behavior genuinely
depends on the Android OS / Google Play Services runtime and cannot be
confirmed without a real device — flagged honestly rather than guessed.

| # | Input / Condition | Expected Behavior | Current Behavior (source-verified) | Status | Recommended Action |
|---|---|---|---|---|---|
| 1 | Bluetooth turned OFF, then back ON | Discovery/advertising fails gracefully, no crash, and resumes automatically once the radio is back | `startAdvertising()`/`startDiscovery()` attach `addOnFailureListener { e -> Log.e(...) }` — failure is logged, not thrown, no crash. **Bulk Sprint 3: FIXED the resume half** — `MeshForegroundService` now registers a `BroadcastReceiver` for `BluetoothAdapter.ACTION_STATE_CHANGED` and calls `startDutyCycle()` again on a transition to `STATE_ON`. No new permissions needed (BLUETOOTH already declared for Nearby Connections itself). Not validated on real hardware. | **Fixed this pass** (unvalidated) | None further planned; real-device validation is the remaining step |
| 2 | Wi-Fi turned OFF, then back ON | Same as above (Nearby Connections uses both Bluetooth and Wi-Fi Direct depending on strategy) | Same failure-listener pattern as row 1 for the OFF case. **Bulk Sprint 3: FIXED the resume half** — the same `BroadcastReceiver` also listens for Wi-Fi's `WIFI_STATE_CHANGED_ACTION` and resumes on `WIFI_STATE_ENABLED`. | **Fixed this pass** (unvalidated) | None further planned; real-device validation is the remaining step |
| 3 | Nearby Connections API unavailable (Play Services missing/outdated) | App should not crash; mesh should degrade to "unavailable" rather than silently do nothing | `Nearby.getConnectionsClient(context)` is called once in the constructor with no try/catch around it. If this throws (e.g. `Nearby` module not present), it would propagate up through `NearbyConnectionsManager`'s constructor, which is called from `MeshForegroundService.onCreate()`, which — as an unguarded exception during service creation — would crash the app process. **Not verifiable from source alone whether `getConnectionsClient` can actually throw in this way**; the GMS API contract is not fully documented in the reviewed files. | Unverified / possible gap | Flagged, not fixed — wrapping the constructor call in try/catch and surfacing a "mesh unavailable" state to Dart would be the safe fix, but doing so without being able to actually trigger the failure on a device risks masking a real crash with a silent no-op instead. Needs real-device testing before changing. |
| 4 | Permission denied (nearby devices / location, depending on Android version) | Advertising/discovery calls fail cleanly | Same `addOnFailureListener` pattern as row 1 covers this at the Nearby Connections API level (a permission failure surfaces as a failed task, same as any other). **Not verified**: whether `MainActivity`/the app's permission-request flow actually requests all permissions Nearby Connections needs on the OS versions SETU targets — that is a Dart/platform-config concern, out of this native-file-scope audit. | Partially verified | Out of scope for this pass — belongs in a permissions/platform-config audit, not the mesh-relay audit |
| 5 | No peers ever found | App should remain functional, not hang | `discoveryLatencyMicros` simply stays `0L` forever (reported to Dart as "not measured", never a fake zero). No timeout, no error state — this is not a failure, it's a valid steady state for an isolated device | Confirmed OK | None |
| 6 | Peer disconnects mid-transfer | Cleanup, no crash, queue keeps draining to other peers | `onDisconnected` removes the endpoint from `connectedEndpoints`/`connectionStartedAtNanos`, notifies `listener.onPeerDisconnected`. `broadcastBytes()` iterates only currently-connected endpoints, so a mid-iteration disconnect at worst means that peer doesn't get that one payload — no crash, no queue block | Confirmed OK | None |
| 7 | Peer reconnects after disconnect | Should reconnect cleanly, not error out or duplicate-connect | Re-discovery goes through the normal `onEndpointFound` → tie-break → `requestConnection`/wait path. **No cooldown/backoff** — a rapidly flapping connection (marginal range) will repeatedly attempt full reconnect with no throttling | Gap (known, not fixed) | Exponential backoff per endpoint is a real, scoped feature — not a one-line guard, needs real-hardware validation of the backoff timing before shipping. See `NATIVE_MESH_AUDIT.md` §12 |
| 8 | Internet unavailable at all connected peers | Packets stay queued at every hop, no crash | Purely a Dart-layer concern (`hasRealInternet()`/`LocalQueueService`) — native has no awareness of connectivity beyond the `allowRelay`/`allowUpload` policy flags pushed to it. No native-layer action needed or taken | Confirmed OK (native has no role here) | None |
| 9 | Internet restored at a peer | That peer should start uploading queued packets | Same as row 8 — entirely Dart's `_retryPendingUploads()` 30s timer, native uninvolved | Confirmed OK (native has no role here) | None |
| 10 | Backend unavailable (peer has internet but backend is down) | Native uninvolved; Dart retries | Confirmed — native has no visibility into backend reachability at all, only the generic connectivity policy flags | Confirmed OK (native has no role here) | None |
| 11 | Malformed packet bytes received | Dropped without crashing native | Re-verified directly against `PacketRelayEngine.kt:224-229`: `JSONObject(String(bytes))` is wrapped in `try { ... } catch (e: Exception) { return@synchronized RelayResult(isNew = false, relayBytes = null) }` — malformed bytes are caught and dropped cleanly, no crash. A missing/empty `packet_id` field is also separately guarded (`json.optString("packet_id", "").isEmpty()` → dropped) | **Confirmed OK** (re-verified this pass) | None |
| 12 | Signature-invalid packet (would be rejected by Dart) | Native has no signature check, so this is not a native-layer scenario — native relays it regardless | Confirmed — see `NATIVE_MESH_AUDIT.md` §5. Dart's own receive path independently verifies and drops it, so an end-to-end invalid packet is still rejected before being acted on, but it **is** relayed one more hop by any backgrounded native-only devices in between | Confirmed gap (documented, not fixed) | See `NATIVE_MESH_AUDIT.md` §5 — real fix is porting signature verification into Kotlin, out of scope this pass |
| 13 | Replayed (previously-seen) packet | Should be recognized as a duplicate and not re-relayed | `seen.contains(packetId)` check in `process()`, now inside `synchronized(lock)` — confirmed correct and now thread-safe | Confirmed OK (fixed this pass: thread-safety) | None further |
| 14 | Duplicate packet arriving from two different peers near-simultaneously | Should be deduped once, not race into double-relay | This is exactly the race the thread-safety fix in row 13 closes — previously two concurrent `process()` calls could both pass the `seen.contains()` check before either inserted, both relaying. Now serialized via `synchronized(lock)`, so the second call sees the first's insertion | **Fixed this pass** | None further |
| 15 | TTL expired (`ttl <= 0` after decrement) | Not relayed further | `nextTtl()` clamps to `>= 0`; the relay-decision logic in `process()` does not return relay bytes when the resulting TTL would not allow further relay (mirrors `AdaptiveTtl.canRelay`'s intent). Confirmed by reading the decrement/relay-gating logic | Confirmed OK | None |
| 16 | Device battery low / power-saver mode | Relay/discovery behavior should change | Native has **zero direct battery checks** — purely driven by the `allowRelay`/`allowDiscoveryIntervalMs` values Dart pushes via `updateMeshPolicy`. If Dart never sends an update (e.g. the app was killed before ever attaching), native runs at hardcoded full-power defaults indefinitely | Confirmed by design, with one gap: see row 17 | None for the design itself; see row 17 for the restart interaction |
| 17 | App/process killed and native foreground service restarted (`START_STICKY`) | Should resume with the last-known policy, or fail safe | Previously: `onCreate()` rebuilt everything fresh, full-power defaults until Dart re-synced. **Bulk Sprint 3: FIXED for policy + dedup cache** — `MeshStateStore` persists both (30s timer + on explicit policy change + best-effort on `onDestroy()`), and `onCreate()` restores them before discovery starts. `lastKnownLat/Lon` still reset to null (deliberately not persisted — degrades gracefully, see `NATIVE_MESH_AUDIT.md` §16 update). An abrupt OOM-kill can still lose up to one persistence interval's worth of dedup history — accepted, documented trade-off | **Fixed this pass** (unvalidated) for policy/dedup; location intentionally still not persisted | Real-device validation of restore-on-restart behavior is the remaining step |
| 18 | Multiple simultaneous packets arriving from several peers at once | Must all be processed correctly, no lost/corrupted state | This is the general case rows 13/14's thread-safety fix protects — `process()`'s full body (dedup, location tracking, echo tracking, counters) is now atomic per-call via `synchronized(lock)`. Throughput is serialized (no genuine parallelism inside `process()`), which is the correct trade-off for correctness over raw throughput at mesh-relay volumes | Confirmed OK (fixed this pass) | None |

## Summary (updated Bulk Sprint 3)

- **Confirmed OK, unchanged**: rows 5, 6, 8, 9, 10, 11 (re-verified), 15.
- **Fixed in Bulk Sprint 2**: rows 13, 14, 18 (thread-safety), and the
  reconnection guard underlying row 7's "already-connected" sub-case.
- **Fixed in Bulk Sprint 3**: rows 1, 2 (Bluetooth/Wi-Fi auto-resume), 7
  (bounded backoff for failed connection attempts, though the "connects
  then quickly disconnects" flapping sub-case is still explicitly not
  covered), 17 (policy + dedup-cache persistence across `START_STICKY`
  restart, though `lastKnownLat/Lon` is deliberately still not persisted).
  **None of these are validated on real hardware** — fixed at the
  source-review level, per this sandbox's confirmed lack of any
  build/device toolchain.
- **Real gaps, still documented but not fixed** (each requires a scoped
  feature addition or a product/security decision this sandbox cannot
  make alone): connection-level authentication (`NATIVE_MESH_AUDIT.md` §3,
  see `docs/security/NATIVE_CONNECTION_AUTH_DESIGN.md`), native signature
  verification (row 12 -- `NATIVE_MESH_AUDIT.md` §5, see
  `docs/security/NATIVE_SIGNATURE_VERIFICATION_DESIGN.md` — blocked on an
  unresolvable Maven dependency in this sandbox, not a design gap).
- **Out of this audit's scope**: rows 3 (GMS availability) and 4
  (permission flow) — platform/config concerns, not mesh-relay logic.
