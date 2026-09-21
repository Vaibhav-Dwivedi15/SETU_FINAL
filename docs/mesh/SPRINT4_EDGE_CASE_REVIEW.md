# Sprint 4 — Edge-Case Review: State Persistence, Reconnect Backoff, Radio Resume

Owner: Vib (Mesh/Architecture). Written Sep 21 2026, Bulk Sprint 4, §9/§11/§12.

This is a **review pass**, not a rewrite — Sprint 3 implemented all three
mechanisms below; this document is a deliberate second look at the edge
cases the brief calls out, based on actual source re-reading (not assumed
behavior), with any finding stated honestly whether it's a real gap or a
confirmation that the existing design already handles it.

## 1. START_STICKY / dedup persistence (`MeshStateStore`, `PacketRelayEngine`, `MeshForegroundService`)

| Edge case | Reviewed behavior | Verdict |
|---|---|---|
| Corrupt/unreadable SharedPreferences file | `loadPolicy()`/`loadSeenIds()` go through the standard `SharedPreferences` API, which is itself responsible for handling a corrupt backing file (Android's implementation falls back to an empty preference set rather than throwing) — `prefs.contains(...)`/`prefs.getString(..., null)` degrade to "nothing persisted" exactly like a fresh install. No custom corruption handling was added because none is needed: the framework API already returns safe defaults rather than throwing. | No gap — confirmed by API contract, not newly hardened. |
| Empty state (fresh install, nothing ever persisted) | `loadPolicy()` returns `null` → caller keeps its pre-existing hardcoded defaults (`currentDiscoveryIntervalMs = 5_000L`, `currentAllowRelay = true`). `loadSeenIds()` returns `emptyList()` → `restoreSeen(emptyList())` is a no-op loop. | No gap — already the documented fallback path. |
| 500th / 501st dedup entry boundary | `snapshotSeen()` returns `seen.toList()`, and `seen` is already bounded to `maxCacheSize` (500) by `remember()`'s own FIFO eviction *before* any snapshot is ever taken — persistence never sees more than 500 entries because the in-memory cache itself never holds more than 500. `restoreSeen()` re-inserts through `remember()`, which re-applies the same 500-entry FIFO bound on the way back in, so a persisted snapshot can never inflate the cache past its normal ceiling either. | No gap — the bound is enforced on both write and read paths by the same existing `remember()` logic, not duplicated or reimplemented in `MeshStateStore`. |
| Restart with an empty/never-persisted cache | Identical to the "fresh install" row above — `restoreSeen(emptyList())` is a no-op, service starts with a genuinely empty `seen` set exactly as it always did before Sprint 3, no regression. | No gap. |
| Duplicate or stale IDs in a persisted snapshot | `saveSeenIds()` is fed directly from `snapshotSeen()`, which is itself `seen.toList()` — a `LinkedHashSet`, so it is structurally impossible for the snapshot to contain a duplicate ID in the first place. "Stale" (i.e., an ID for a packet whose TTL has long since expired everywhere else) is not a bug: dedup by `packet_id` alone was always independent of packet age — the original in-memory design already treats "seen once" as permanent (barring the location-based re-entry exception), and persistence doesn't change that contract, only how long "permanent" can outlive a single process lifetime. | No gap — matches pre-existing dedup semantics, not a new risk introduced by persistence. |
| Rapid restart (service killed and restarted faster than the 30s persistence tick) | Documented, accepted trade-off already stated in `MeshStateStore`'s own doc comment: up to one `statePersistenceIntervalMs` (30s) window of dedup history can be lost if the process is killed abruptly enough that neither the periodic tick nor `onDestroy()`'s best-effort final `persistSeenSnapshot()` runs (e.g. the OS OOM-killer, which does not guarantee `onDestroy()` executes). This is explicitly **not** treated as a correctness bug in the existing docs: a packet that slips back through as "new" after such a loss is still bounded by TTL and still caught by every *other* device's independent dedup cache — it is the same class of behavior as any single device's cache evicting an old entry under normal FIFO pressure. | Confirmed pre-existing, accepted trade-off — not re-litigated this pass. |
| Unbounded-value risk (a single `putString` growing without limit) | `KEY_SEEN_IDS` is a comma-joined string of at most 500 packet IDs, each of the fixed shape `<8-hex-char-shortSenderId>-<micros>` (roughly 26–30 characters) — worst case an ~15KB string, well within `SharedPreferences`' practical single-value limits (Android does not hard-cap `putString` length, but a multi-MB value would be a real anti-pattern; this is nowhere close). No unbounded growth path exists because the source (`seen`) is itself capped before the string is ever built. | No gap. |
| Stale policy accidentally enabling unrestricted relay after a restart | `currentAllowRelay` defaults to `true` (full relay) exactly as it always did *before* persistence existed — a persisted `allowRelay=false` (a deliberately throttled battery tier) is what gets restored, which is *more* restrictive than the old always-full-power default, never less. There is no code path by which a persisted value could grant a relay device MORE capability than the codebase's own original default already allowed; the only direction persistence can move `allowRelay` is toward whatever Dart itself last explicitly set, which is by definition a value the app already considered a valid state for this device to be in. | No gap — persistence cannot escalate relay privilege beyond what the app's own Dart layer already granted at some point. |

**Net finding for §9/§10**: no new defect found in this review pass. The
design already handles every edge case the brief names, most by
construction (bounding happens once, in `PacketRelayEngine.remember()`,
and both the persist and restore paths route through it) rather than by
adding separate defensive logic in `MeshStateStore`.

## 2. Reconnect backoff / radio resume (`NearbyConnectionsManager`, `MeshForegroundService`)

| Edge case | Reviewed behavior | Verdict |
|---|---|---|
| First discovery of an endpoint is not delayed | `canAttemptConnection(endpointId)`: `lastConnectionAttemptAtNanos[endpointId] ?: return true` — an endpoint with no prior failed attempt has no map entry at all, so the very first connection attempt to any newly-discovered endpoint always proceeds immediately, with zero backoff. Backoff only ever applies starting from the *second* attempt to the *same* endpoint, after a first one has already failed. | No gap. |
| Backoff is per-endpoint, not global | Both `connectionFailureCount` and `lastConnectionAttemptAtNanos` are keyed by `endpointId` (`MutableMap<String, ...>`) — a slow/failing connection to one nearby device cannot delay or block a fresh attempt to a different device discovered at the same time. There is no shared/global backoff counter anywhere in this class. | No gap. |
| Receiver double-registration / cleanup (`radioStateReceiver`) | `registerRadioStateReceiver()` is called exactly once, from `onCreate()`, which itself runs at most once per `Service` instance (standard Android lifecycle guarantee — `onCreate()` is not re-invoked for an existing instance, including on a `START_STICKY` redelivery, which calls `onStartCommand()` again but not `onCreate()`). `onDestroy()` unregisters the same receiver reference and nulls the field. There is no code path that calls `registerRadioStateReceiver()` a second time on a still-live instance, so double-registration cannot occur under this service's actual lifecycle. | No gap. |
| Rapid Bluetooth/Wi-Fi OFF→ON→OFF storm | Each `ACTION_STATE_CHANGED`/`WIFI_STATE_CHANGED` broadcast that reports the radio as back `ON` calls `startDutyCycle()` again. `startDutyCycle()` was already idempotent-safe before this sprint (existing "don't double-start in the current tier" guard, confirmed by source review, not changed this pass) — so a rapid toggle storm results in redundant-but-harmless repeated calls into an already-idempotent function, not accumulating state, leaked handlers, or duplicate advertising sessions. This was deliberately NOT hardened further (e.g. with an explicit debounce/coalescing timer) — see the class-level comment in `MeshForegroundService.kt`: scope was kept to "resume on ON", not "distinguish why it turned on", which is enough to close the actual gap (mesh silently staying off forever) without inventing an unvalidated debounce duration for a scenario (a user rapidly toggling radios) that is not the sprint's stated problem. | No gap for the stated scope; a debounce is explicitly out of scope, not silently missing. |
| Existing duty-cycle logic reused, not duplicated | `registerRadioStateReceiver()`'s handler calls the *existing* `startDutyCycle()` — no new advertise/discover invocation logic was written for radio-resume; it reuses the exact same code path `updateMeshPolicy()` already calls on every policy change. | Confirmed — no duplication. |

**Net finding for §11/§12**: no new defect found. The one deliberate
scope boundary (no debounce for rapid radio toggling) is restated here
as an explicit, reasoned decision — not something this review is
silently leaving unexamined.

## Scope note

Per the Sprint 4 "no feature creep" rule, this review pass added **zero**
new code — every row above is a reasoned conclusion from re-reading the
actual Sprint 3 source (`MeshStateStore.kt`, `PacketRelayEngine.kt`,
`MeshForegroundService.kt`, `NearbyConnectionsManager.kt`), not a
speculative worst case. Where a real gap had existed, Sprint 3 already
closed it; this pass exists to confirm that with fresh eyes, not to
re-litigate settled design decisions without new evidence.
