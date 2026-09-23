# SETU — Block 1: Mesh Stability + End-to-End Correctness

Branch: `feature/mesh-stability-final` (from `feature/vib-integration-validation` @ `604e936`).
Scope: fix defects in the existing mesh. No architecture change: Nearby
Connections, `P2P_CLUSTER`, Ed25519, packet types, `signaturePayload`,
`MAX_TTL = 5`, ACK semantics and battery thresholds are unchanged.

Status vocabulary: IMPLEMENTED · VERIFIED (executed, evidence below) ·
PARTIALLY VERIFIED · SOURCE REVIEW · BLOCKED · UNTESTED · KNOWN LIMITATION.
**Nothing here is device-verified: no physical Android device was available
(`adb devices` empty).**

## 1. Problems found (from the pre-device audit, re-checked against source)

| # | Problem | Confirmed in source |
|---|---|---|
| 1 | `MeshLocator`/`MeshServiceImpl` created lazily (first SOS/recovery/readiness) | yes — only 3 call sites |
| 2 | Native forwards payloads with no Dart listener → dropped after being marked *seen* | yes — `eventSink?.success` on a null sink |
| 3 | Native **and** Dart both rebroadcast relays (two TTL computations) | yes |
| 4 | Native had no size/age guard | yes |
| 5 | ttl ≤ 0 packet admitted to native `seen` → suppresses genuine copy | yes |
| 6 | Termination fail-open when registry empty; registry memory-only | yes |
| 7 | Queue sweep used `LIKE` with unescaped `%`/`_` | yes |
| 8 | Persisted native policy could keep relay off after charging | yes |
| 9 | Connection edge cases (name collision, unobserved `requestConnection` failure, backoff reset by any success) | yes |
| 10 | **New:** native timestamp parse read a 6-digit fraction as milliseconds (+≈2 min skew) | yes — `SimpleDateFormat "SSS"` |
| 11 | **New:** a rejected `/ingest` packet (HTTP 200 + `rejected[]`) was marked delivered and ACKed | yes |
| 12 | **New:** ACK/alert packets sat in the upload queue and were re-posted every 30 s | yes |
| 13 | **New:** release build (R8) had never been run and fails | yes — reproduced |
| 14 | **New:** CI ran a Gradle target that fails on a third-party plugin's tests | yes — reproduced |

## 2. Problems fixed

1–2. **Eager start + handoff.** `MeshLocator.start()` is called from `main()`
(wrapped, non-blocking, no permission/network dependency). Because a
Dart listener can still be absent (service revived without an Activity,
first frames), native also keeps a **bounded FIFO `HandoffBuffer`**
(64 events ≈ ≤256 KB, drop-oldest, counted) flushed on `onListen` /
service bind. Dedup and relay are *not* delayed; only the Dart-bound copy is held.
`originate` now returns `SERVICE_UNAVAILABLE` instead of a silent success when the service is unbound.

3–4. **One relay path = native.** `NearbyService.relaysNatively` (true for
`PlatformNearbyService`) makes `MeshServiceImpl` skip its own relay.
Native works without Dart, has jitter/echo suppression and the battery
guard, and is the only place the relay TTL is computed. Transports with
no native engine (the test simulation) keep Dart relaying.
Native is told about closed emergencies (`closeEmergency`) so termination
still stops relaying/delivery (Dart used to purge its own relay queue).

5. **Native guards** (order: size → parse → packet_id → **signature** → age
→ closed-emergency → ttl range → dedup → relay):
size > 4096 B, age > 5 min, > 30 s in the future (mirrors Dart), unparseable
timestamp. Timestamp parser rewritten to accept exactly what Dart emits.

6. **Seen-cache poisoning.** ttl outside 1..5 is rejected *before* dedup
admission (Dart's validator rejects those too). Stale/invalid packets never
reach admission either.

7. **Termination.** Registry persisted (`SharedPreferences`), reloaded before
each check, **fail-closed when empty**. Cleanup selects by decoding each
row and comparing `emergency_id` for equality, deleting by primary key.

8–9. **Battery.** `BatteryPolicy` (pure) — same thresholds/values as Dart —
applied at service start from the real battery level (persisted policy is
now only a fallback) and on `ACTION_BATTERY_CHANGED`. battery_plus 7.1.1's
Android source publishes on every such broadcast with no de-duplication, so
the Dart stream *does* fire on percentage changes; **no polling added**.

10. **Connections.** `ConnectionBackoff` (pure): failure on
`requestConnection` counted, connect→drop within 5 s counts as a failure,
only a stable connection clears history, bounded to 128 endpoints;
32-bit random endpoint name (was 9000 values); `onEndpointLost` cleans the
pending latency stamp; radio ON events coalesced into one duty-cycle restart;
"already advertising/discovering" logged at info.

11. **Upload outcome.** `/ingest` per-packet result is parsed:
accepted / duplicate → delivered + ACK; rejected → stop retrying, **no ACK,
not counted delivered**; failed (offline, non-2xx, non-contract body) → retry.

12. ACK/alert packets no longer enter the durable upload queue.

13. `proguard-rules.pro`: `-dontwarn` for unused Play Core (rules R8 generated).
14. CI: `./gradlew :app:testDebugUnitTest`.

## 3. Files changed

Kotlin main: `PacketRelayEngine.kt`, `MeshForegroundService.kt`,
`NearbyConnectionsManager.kt`, `MeshChannelHandler.kt`; new `HandoffBuffer.kt`,
`BatteryPolicy.kt`, `ConnectionBackoff.kt`; `proguard-rules.pro`.
Dart: `main.dart`, `core/services/mesh_locator.dart`, `mesh/services/{mesh_service,nearby_service,responder_registry,local_queue_service,mesh_metrics,adaptive_ttl}.dart`,
`services/{backend_service,battery_service}.dart`.
Tests: `PacketRelayEngineTest.kt` (+24), `CrossLanguageVectorTest.kt`,
`test/block1_mesh_test.dart`, `test/cross_language_signature_test.dart`,
`test/mesh_harness_test.dart`, `test/mesh_simulation.dart`;
`tools/cross_lang/verify_python.py`; `.github/workflows/setu-ci.yml`.

## 4. Architecture decisions

* **Native is the authoritative relay path** (only layer that works without Dart;
  already owns jitter, echo suppression, battery guard, TTL). Consequence,
  stated plainly: in production Dart's `PriorityRelayQueue` ordering and the
  dense-cluster extra TTL decrement no longer apply (native gives critical
  packets a shorter jitter, and native has no peer census). Both remain for
  non-native transports and stay unit-tested.
* **Buffer, not delayed dedup.** Dedup admission is unchanged; only delivery to Dart is buffered.
* **Fail-closed termination** is a behaviour change: until a responder is
  provisioned on the backend *and* synced once, no mesh termination takes effect.
  (No producer of terminations exists anyway.)
* Size check runs **before** parsing (cheapest, cannot admit anything); age
  runs **after** signature verification so the timestamp is trusted.

## 5. Tests added

| Area | Tests |
|---|---|
| Native size 4095/4096/4097; age fresh/limit/stale/future/skew/unparseable; µs timestamp | Kotlin |
| ttl 0, 1, 5, negative, missing, non-numeric, >5; poisoning regression (ttl=0 then genuine); invalid-sig then genuine; stale then fresh | Kotlin |
| Closed emergency; bounded closed set; `nextTtl` matrix (stale/critical/oversized) | Kotlin |
| `HandoffBuffer`: before/after listener, FIFO, no duplicate, bounded, partial flush | Kotlin |
| `BatteryPolicy` thresholds + recovery; `ConnectionBackoff` failure/retry/flap/reset/bound/clear | Kotlin |
| Eager start: one `MeshLocator`, one event subscription, events reach Dart before SOS, malformed event survives | Dart |
| One relay path (native transport ⇒ 0 Dart broadcasts; otherwise exactly 1); duplicate delivery dropped | Dart |
| Upload: accepted→ACK; rejected→no ACK & no endless retry; failed→pending; ACK/alert not queued; response parsing; HTTP mock | Dart |
| Termination: authorized / unauthorized / empty registry / restart persistence / empty-backend-answer | Dart |
| Cleanup: `%`, `_`, literal `%`, alphanumeric, malformed rows, empty id | Dart |
| Battery tiers + policy per tier + recovery | Dart |
| Cross-language: 5 genuine + 10 tampered + 1 relay-rewrite vector | Dart, Kotlin, Python |

## 6. Test results (executed this session, on this machine)

| Command | Result |
|---|---|
| `flutter test` | **145 / 145 passed** (baseline 121) |
| `flutter analyze lib test` | 0 errors, 0 warnings, 13 infos (pre-existing lint style) |
| `./gradlew :app:testDebugUnitTest` | **44 / 44** `PacketRelayEngineTest` passed (baseline 20); `CrossLanguageVectorTest` SKIPPED without env |
| `SETU_XLANG_DIR=… ./gradlew :app:testDebugUnitTest --tests '*CrossLanguageVectorTest*'` | **16 vectors verified in Kotlin**, 0 failures |

Native tests run with the **real `org.json`** from Maven and real BouncyCastle
via Gradle — the earlier shim caveat no longer applies.

## 7. Gradle result (JBR 21, Gradle 9.1.0, Android SDK 36, offline-capable)

| Task | Result |
|---|---|
| `:app:testDebugUnitTest` | VERIFIED — success |
| `:app:assembleDebug` | VERIFIED — success; BouncyCastle `Ed25519Signer` present in dex; merged manifest keeps `MeshForegroundService` `exported=false`, `foregroundServiceType=connectedDevice` |
| `flutter build apk --release` (R8 + shrink) | **First run FAILED** (missing Play Core classes); fixed; now VERIFIED — success, 58.2 MB; `SignatureVerifier` retained; service type `0x10` (connectedDevice) in the release manifest |
| bare `./gradlew testDebugUnitTest` (all modules) | FAILS in third-party `geolocator_android` tests (Mockito) — not SETU code; CI now targets `:app` |

The release APK is signed with the **debug key** (no `key.properties`) — not distributable.

## 8. Cross-language result

Dart signs (real `SigningService`, real packet models, real wire encoding) →
Kotlin (`SignatureVerifier.verifyPacket` + full `PacketRelayEngine.process`) →
Python (`Backend/app/services/signature_service.verify_signature`, unmodified).

| | genuine (emergency ×2 incl. µs timestamp, unicode/pipe/quote message, whole-degree coords; termination; relay ttl/hop rewrite) | tampered (message, timestamp, latitude, longitude, sender_id, signature, priority, nonce, packet_id, emergency_id) |
|---|---|---|
| Dart | verify ✔ | all fail ✔ |
| Kotlin | verify ✔ (ack and alert too) | all fail ✔ |
| Python | verify ✔ (ack/alert skipped: not accepted by `/ingest`) | all fail ✔ |

Status: **VERIFIED** for these vectors on this machine (JVM, Dart VM, CPython).
Caveat: the Python check uses a stand-in object instead of pydantic `PacketIn`
(pydantic not installed here); payload building and verification are production code.
Not covered: on-device Android Keystore keys, coordinates below ~1e-4°
(Python `1e-05` vs Dart `1e-5` formatting), non-Dart-emitted timestamp forms.

## 9. Remaining limitations

* **KNOWN LIMITATION – TTL is unsigned.** A neighbour can still re-send a genuine
  packet with `ttl=1` first: it is delivered (correct — terminal hop) but
  marks the id seen, so the full-TTL copy is then suppressed on that node.
  Fixing needs a signed TTL (format change) or upgrade-relay logic; out of scope.
* **KNOWN LIMITATION – handoff buffer is in-memory**; a process kill loses it.
* Native has no per-sender nonce cache; replay within the 5-min window relies on the 500-entry `seen` cache.
* `updateLocation` is only sent at SOS time, so location-based re-entry is effectively dormant.
* `SosRepository` still uploads directly in addition to `originate`'s upload; harmless now (second answer = `duplicate` = delivered).
* SQLite delete in `markEmergencyClosed` is SOURCE REVIEW; the selection logic is tested, the DB call is not (no sqflite test runner available offline).
* **Backend follow-ups for BLOCK 2 (not changed here):** (a) forged packet_id squatting makes the genuine packet answer `duplicate packet_id`, which the client treats as delivered; (b) `/ingest` returns 200 for rejections (client now copes); (c) backend expiry 3600 s vs Dart 300 s vs AI 300 s; (d) ACK is client-attested, not backend-attested; (e) backend has no ack/alert types.
* Wi-Fi radio-resume uses `WIFI_STATE_CHANGED_ACTION` on a runtime-registered receiver; behaviour on every Android version is UNTESTED.
* No termination producer exists (unchanged, documented).

## 10. Device test prerequisites

1. ≥ 2 (ideally 3) Android 12–14 phones; Bluetooth, location, Nearby-devices permissions granted; Wi-Fi/BT on.
2. A responder key provisioned on the backend and synced (else terminations are — by design — rejected).
3. Install the **debug** APK (`app-debug.apk`); use `adb logcat -s MeshForegroundService NearbyConnectionsManager MeshService`.
4. Scenarios to run: cold start with app never opened past login → confirm upload at an internet-connected node
   (P0-2); kill Activity, receive packet, reopen → flushed (`Flushed N buffered…`); battery <20 → >20 while process restarted;
   airplane-mode toggle → duty-cycle resumes once (watch for a single "resuming duty cycle" restart); reconnect after walking out of range and back (backoff paces our attempts).
5. Read `MeshMetrics.snapshot()` counters (signature/validation/native drops, upload attempts/rejected/retries, ACKs, terminations, battery mode).

## 11. Final status matrix

| Item | Status | Evidence |
|---|---|---|
| Eager Dart start, single instance, listener attached | VERIFIED (VM, mocked channels) | `block1_mesh_test` "eager start" |
| Native→Dart handoff buffer logic | VERIFIED (JVM) | `HandoffBuffer` tests; service wiring SOURCE REVIEW |
| Single relay path | VERIFIED (simulation) / native wiring SOURCE REVIEW | relay tests |
| TTL consistency | VERIFIED (JVM matrix) | `nextTtl_matrix`, relay-path tests |
| Native size/age guards | VERIFIED (JVM) | boundary tests |
| ttl=0 / stale / invalid poisoning regressions | VERIFIED (JVM) | regression tests |
| ttl=1 terminal-hop suppression | KNOWN LIMITATION | §9 |
| Termination fail-closed + persistence | VERIFIED (VM) | termination group |
| Exact emergency cleanup | VERIFIED (selection logic) / SQL call SOURCE REVIEW | cleanup group |
| Battery tiers (Dart + native) | VERIFIED (pure logic); receiver wiring UNTESTED on device | tier tests |
| battery_plus emits on level change | VERIFIED from plugin source; UNTESTED on device | plugin 7.1.1 `BatteryPlusPlugin.kt` |
| Connection backoff / flap / reset | VERIFIED (JVM, pure class); Nearby wiring UNTESTED | `ConnectionBackoff` tests |
| Radio recovery | SOURCE REVIEW (registered once, unregistered in `onDestroy`, coalesced); UNTESTED | — |
| Upload outcome / ACK correctness | VERIFIED (VM) | upload tests |
| Real Gradle debug build | VERIFIED | §7 |
| Real release/R8 build | VERIFIED after fix | §7 |
| Cross-language signature | VERIFIED (on this machine) | §8 |
| Real-device behaviour of any of the above | UNTESTED | no device |
