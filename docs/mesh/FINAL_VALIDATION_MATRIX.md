# SETU Mesh — Final Validation Matrix

Owner: Vib (Mesh/Architecture). Written Sep 21 2026, Bulk Sprint 4, §34.

The purpose of this table is a single honest place that separates **"code
exists"** from **"code compiled"** from **"code verified by an executed
test"** from **"code verified on a real device."** These are four
different claims, and across four sprints of work in a sandbox with no
Flutter/Android SDK and no physical devices, conflating them would be the
single easiest way to accidentally overstate what's actually known to
work. Every row below is graded against the real, confirmed state of this
sandbox as of Sprint 4 — not against what would probably be true on a
real machine.

**Column definitions**:
- **Source Reviewed**: the logic was read and manually traced against its
  spec/design doc.
- **Implemented**: the code exists in the repo, on the current branch.
- **Compiled**: the exact production file was compiled by a real
  Kotlin/Dart/Gradle toolchain (standalone `kotlinc`/`javac` counts only
  when it compiled the REAL file, not a copy — see notes column).
- **Unit Tested**: a test exists AND was actually run with real captured
  output (not just written).
- **Device Tested**: exercised on real hardware, with an operator log
  entry (see `MULTI_DEVICE_TEST_PLAN.md`).
- **Status**: CODE EXISTS (written, not run) / CODE COMPILED (built, not
  run) / CODE VERIFIED (unit-tested with real output) / DEVICE VERIFIED
  (real hardware, real result).

| # | Feature | Source Reviewed | Implemented | Compiled | Unit Tested | Device Tested | Status | Notes |
|---|---|---|---|---|---|---|---|---|
| 1 | Recovery ACK (Dart `_originateAck`/lifecycle) | Yes | Yes (pre-existing) | No (Dart SDK unavailable) | No | No | CODE EXISTS | Predates this sprint; no Dart toolchain in this sandbox across all 4 sprints. |
| 2 | Dart-side dedup (`PacketService`) | Yes | Yes (pre-existing) | No | No | No | CODE EXISTS | Same Dart-toolchain blocker. |
| 3 | Native dedup (`PacketRelayEngine.seen`) | Yes | Yes | No (needs `org.json`, unavailable — see `NATIVE_TEST_INFRASTRUCTURE.md`) | Partial — the pure logic path has no dedup-cache-specific unit, but its FIFO-eviction/500-cap behavior was manually traced against `remember()`'s source this sprint (§1 of `SPRINT4_EDGE_CASE_REVIEW.md`) | No | CODE EXISTS | Real integration test exists (`PacketRelayEngineTest.kt`) but not executed — see row 13 for why. |
| 4 | TTL / Adaptive TTL (`nextTtl`) | Yes | Yes | **Yes** — standalone `kotlinc`, no Android/org.json dependency | **Yes** — 13/13 real JUnit assertions passed (`tools/NativeLogicTest.kt`) | No | CODE VERIFIED | The one piece of `PacketRelayEngine` with no missing-dependency blocker; genuinely executed, real output captured this sprint. |
| 5 | Relay decision / rebroadcast (`process()`'s relay branch) | Yes | Yes | No (`org.json`) | No (real test written, not executed — see row 13) | No | CODE EXISTS | |
| 6 | Store-and-forward (local queue durability) | Yes | Yes (pre-existing) | No | No | No | CODE EXISTS | Dart-side, same toolchain blocker as rows 1-2. |
| 7 | Exit node / backend upload | Yes | Yes (pre-existing) | No | No | No | CODE EXISTS | |
| 8 | Battery-tiered duty cycling | Yes | Yes (pre-existing) | No (Android-dependent, needs full SDK) | No | No | CODE EXISTS | |
| 9 | START_STICKY state persistence (`MeshStateStore`) | Yes | Yes | No (Android `SharedPreferences`-dependent, needs full SDK) | No | No | CODE EXISTS | Edge cases reasoned through in `SPRINT4_EDGE_CASE_REVIEW.md` §1 — no defect found, but "reasoned through" is not "executed." |
| 10 | Reconnection backoff (`NearbyConnectionsManager`) | Yes | Yes | No (GMS Nearby Connections-dependent, needs full SDK) | No | No | CODE EXISTS | Edge cases reasoned through in `SPRINT4_EDGE_CASE_REVIEW.md` §2. |
| 11 | Bluetooth/Wi-Fi radio resume | Yes | Yes | No (Android `BroadcastReceiver`-dependent) | No | No | CODE EXISTS | |
| 12 | MAX_TTL drift diagnostic | Yes | Yes | No (spans Dart + native, both blocked) | No | No | CODE EXISTS | Logging-only, non-enforcing by design — see `docs/mesh/TTL.md`. |
| 13 | **Native signature verification (`SignatureVerifier`)** | Yes | Yes | **Partial** — the underlying BouncyCastle Ed25519 calls were proven correct via a standalone Java harness (`tools/Ed25519VectorTest.java`, real executed output, `docs/security/NATIVE_SIGNATURE_TEST_VECTOR.md`) and the raw-JSON-number-extraction regex was proven separately (`tools/RawFieldExtractTest.java`, 10/10 real passes) — but `SignatureVerifier.kt` **itself**, as a Kotlin file, has never been compiled (blocked by the missing `org.json` dependency, not by BouncyCastle or by Kotlin itself — see `NATIVE_TEST_INFRASTRUCTURE.md`) | No (real test written — `PacketRelayEngineTest.kt` — but not executed) | No | **CODE EXISTS, PRIMITIVES VERIFIED** | The most important row in this table to read carefully: the CRYPTO PRIMITIVE is proven correct with real executed output; the KOTLIN FILE wiring it up is not compiled or tested. These are genuinely different claims and this sprint does not conflate them. |
| 14 | Connection authentication | Yes (design doc only) | **No — explicitly not implemented, by design** | N/A | N/A | N/A | DESIGNED, NOT IMPLEMENTED | `docs/security/NATIVE_CONNECTION_AUTH_DESIGN.md` — 4 options compared, "DECISION REQUIRED FROM TEAM," current behavior (auto-accept) unchanged on purpose. |

## Reading this table honestly

- **Nothing in this table is "DEVICE VERIFIED."** No physical Android
  device has been used anywhere in this four-sprint engagement. Every
  claim of correctness beyond "CODE EXISTS" rests on either manual source
  review or an executed test running in a constrained environment that is
  NOT the real target platform (a standalone JVM harness, not an Android
  runtime).
- **Row 4 (TTL) and the crypto-primitive half of row 13 are the strongest
  evidence in this entire engagement** — they are the only places where
  something was actually compiled AND run, with real captured output,
  rather than reasoned about. Everything else remains, at best, "believed
  correct after careful review."
- **The gap between row 13's two halves (primitive vs. Kotlin file) is
  the single most important thing for whoever picks this up next to
  understand**: getting `org.json:json` resolvable (a dependency problem,
  likely solvable in minutes on a real machine with network access) is
  very plausibly all that stands between "reviewed" and "executed, real
  output" for the entire native signature-verification feature.
