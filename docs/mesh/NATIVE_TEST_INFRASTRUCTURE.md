# Native Mesh — Test Infrastructure Status

Owner: Vib (Mesh/Architecture). Written Sep 21 2026, Bulk Sprint 4, §13/§30.
Supersedes the "fully blocked, no path forward" framing in Sprint 3's
final report — that framing was correct at the time given what had been
checked, but Sprint 4 re-examined the assumption (per this sprint's own
explicit instruction to check local caches before assuming blockage) and
found a real, more specific answer.

## The short version

- **JUnit 4.13.2 is genuinely, locally available** in this sandbox
  (`/opt/gradle-8.14.3/lib/junit-4.13.2.jar`, bundled with the local
  standalone Gradle install) — confirmed this sprint.
- **The Kotlin compiler is ALSO genuinely, locally invocable** in this
  sandbox (`/opt/gradle-8.14.3/lib/kotlin-compiler-embeddable-2.0.21.jar`
  plus its transitive jars, all present in the same directory) — this is
  a **new finding this sprint**, not known or claimed in Sprint 3, which
  only recorded "no `kotlinc` found anywhere" (true as a PATH lookup, but
  incomplete — it exists as a jar, just not as an installed `kotlinc`
  binary).
- **Both were actually exercised**, not just located: a real Kotlin file
  was compiled with this compiler and its output executed under the real
  JUnit runner, with real captured output (§2 below).
- **The remaining, sharper blocker**: `org.json.JSONObject`, which
  `PacketRelayEngine.kt` and `SignatureVerifier.kt` both depend on, is
  **not available anywhere in this sandbox** — confirmed by an exhaustive
  filesystem search (`find / -iname "*.jar"` filtered for anything
  json-related, plus a direct check of `/usr/share/maven-repo` and
  `~/.gradle` caches) — so those two files specifically cannot be compiled
  here, standalone or otherwise. This is a missing-dependency blocker, not
  a missing-compiler blocker — a meaningfully different (and smaller)
  problem than Sprint 3's conclusion implied.
- The actual Android/Gradle build (needed for instrumented tests, and for
  compiling anything that touches `android.*`/GMS APIs such as
  `MeshForegroundService.kt`, `NearbyConnectionsManager.kt`,
  `MeshStateStore.kt`) **remains fully blocked** — no Flutter SDK, no
  Android SDK, anywhere in this sandbox. That part of Sprint 3's
  conclusion is unchanged.

## What was actually done

### 1. `tools/NativeLogicTest.kt` — standalone, ACTUALLY compiled and run

`PacketRelayEngine.kt`'s two companion-object pure functions —
`nextTtl()` and `parseTimestampMillis()` — take no `org.json` or Android
input at all. Their bodies were copied verbatim (byte-for-byte, verified
against the real file, not retyped from memory) into a standalone test
file, compiled with the real `kotlinc` (via the jars above) and run with
the real `org.junit.runner.JUnitCore`. Real, captured command and output:

```
$ java -cp $CP org.jetbrains.kotlin.cli.jvm.K2JVMCompilerKt -no-stdlib -no-reflect -cp $CP -d out NativeLogicTest.kt
(no errors, no warnings)

$ java -cp out:kotlin-stdlib-2.0.21.jar:junit-4.13.2.jar:hamcrest-core-1.3.jar org.junit.runner.JUnitCore NativeLogicTest
JUnit version 4.13.2
.............
Time: 0.061

OK (13 tests)
```

13 tests, covering: normal TTL decrement, stale-non-critical double
decrement, stale-but-critical single decrement, a hostile
`ttl=9999`-style oversized input correctly clamped to `MAX_TTL` before
decrementing, TTL reaching exactly 0, TTL already at 0 staying at 0, a
negative TTL input, TTL never exceeding `MAX_TTL - 1`, ISO-8601 timestamp
parsing with and without milliseconds, and null/empty/garbage timestamp
inputs all correctly returning `null` without throwing.

This is **real, executed evidence** that this specific logic behaves as
intended — not a design claim, not a manual trace.

### 2. `setu_app/android/app/src/test/kotlin/com/setu/mesh/PacketRelayEngineTest.kt` — the real, intended CI test (NOT executed here)

This is the actual Gradle unit-test source (standard
`src/test/kotlin` layout — no extra Gradle wiring needed beyond the
`testImplementation` dependencies added to `build.gradle.kts`). It imports
the REAL `PacketRelayEngine` and exercises `process()` end-to-end,
including the Sprint 4 signature-verification wiring (task #27): a
deliberately-invalid-signature packet must be rejected, must NOT be
admitted into the dedup cache, must increment `signatureFailures` (not
`duplicatesFiltered`), and a missing-signature / malformed-public-key /
oversized packet must all be rejected without throwing.

**This file has NOT been compiled or run in this sandbox.** It needs
`org.json:json` on the classpath (added as a `testImplementation` this
sprint — see the reasoning comment in `build.gradle.kts` for why the
Maven `org.json:json` artifact specifically, not Android's bundled
version, is the standard fix here), and that artifact could not be
resolved (Maven Central network-blocked, confirmed again this sprint).
It is written as what should run in real CI or on a developer machine —
believed correct by careful manual review, cross-checked line-by-line
against `PacketRelayEngine.kt`'s actual logic, but explicitly **not**
claimed as passing, because it has not been executed.

### 3. `tools/Ed25519VectorTest.java`, `tools/RawFieldExtractTest.java`

Carried over/copied into the repo this sprint (previously only referenced
from the scratchpad) — see
`docs/security/NATIVE_SIGNATURE_TEST_VECTOR.md` for the real, executed
Ed25519 sign/verify vector these produced, and its own honest scope
caveats (proves the BouncyCastle primitive, not Dart/Kotlin byte-for-byte
interop).

## Why `PacketRelayEngineTest.kt` wasn't also forced through the standalone-copy trick

`tools/NativeLogicTest.kt` works around the `org.json` gap by testing only
the two functions that don't need it. `PacketRelayEngineTest.kt` doesn't
have that option — the whole point of the Sprint 4 signature-verification
tests is to exercise `process()`'s real dedup/verification interaction,
which is inseparable from `JSONObject`. Faking or stubbing
`org.json.JSONObject` well enough to run these tests would mean testing
against home-made stub semantics, not the real library's — exactly the
kind of "looks like a real result but isn't" gap this engagement's rules
say not to produce. So instead of a misleading green checkmark, this is
reported plainly as: written, reviewed carefully, not executed.

## What's still needed for full native test coverage

1. `org.json:json` resolvable (network access, a local mirror, or a
   vendored jar a developer supplies) — unblocks compiling and running
   `PacketRelayEngineTest.kt` as a plain JVM unit test, no Android SDK
   needed for this part.
2. A real Flutter/Android SDK + working Gradle wrapper — needed for
   anything touching `android.*`/GMS (`MeshForegroundService`,
   `NearbyConnectionsManager`, `MeshStateStore`), and for real
   instrumented (on-device) tests.
3. A real Dart SDK — needed for the cross-language signature vector this
   sprint's `NATIVE_SIGNATURE_TEST_VECTOR.md` explicitly says it could
   NOT produce (Java/BouncyCastle-only vector, not Dart-verified).

None of these three is assumed solvable from inside this sandbox; each is
named so a developer with a real machine knows exactly what unblocks what.
