# SETU — Build and Validation Guide

Owner: Vib (Mesh/Architecture). Written Sep 21 2026, Bulk Sprint 4, §31.

This is a plain statement of what a real developer machine needs to build
and validate each part of SETU, and the exact commands to run. **None of
these commands have been run successfully in the sandbox this engagement's
work was produced in** — that sandbox has no Flutter SDK, no Dart SDK, no
Android SDK, and no network access to Maven Central or the Gradle
distribution servers (see §5 for the exact, confirmed blockers). This
document describes the REQUIRED real toolchain and commands, not a claim
that any of them were executed here.

## 1. `setu_app/` — Flutter/Dart mesh app

### Requirements
- Flutter SDK (stable channel; this project was authored against a recent
  Flutter 3.x — pin the exact version via `flutter --version` on a working
  developer machine and record it here once confirmed, rather than
  guessing a number).
- Dart SDK (bundled with Flutter — no separate install needed).
- Android SDK + a configured `ANDROID_HOME`/`ANDROID_SDK_ROOT`, matching
  `compileSdk`/`targetSdk`/`minSdk` as set by the Flutter Gradle plugin
  (`flutter.compileSdkVersion` etc. in
  `setu_app/android/app/build.gradle.kts` — these resolve from the
  Flutter SDK itself, not hardcoded here).
- A real `setu_app/android/local.properties`, NOT the one currently
  checked into this clone (`sdk.dir=/home/vaibhav/Android/Sdk`,
  `flutter.sdk=/home/vaibhav/snap/flutter/...` — both point at the
  original developer's machine and do not exist anywhere else; this is
  the exact, confirmed blocker documented in the Sprint 3 final report).
  **This file should not be committed at all** — it's meant to be
  machine-local (check `.gitignore`; if it isn't already excluded, that's
  worth fixing separately, but is out of scope for this sprint's "no
  feature creep" rule since it's not itself a mesh/security change).
- Network access to `pub.dev` (Dart package registry) for
  `flutter pub get`.

### Commands (in order)
```bash
cd setu_app
flutter doctor -v            # confirms the whole toolchain is actually wired up
flutter pub get              # resolves Dart dependencies
flutter analyze              # static analysis — catches type errors, unused imports, etc.
flutter test                 # runs Dart unit/widget tests
cd android
./gradlew assembleDebug      # builds the Android app, including the native Kotlin mesh layer
```

`./gradlew assembleDebug` (or an equivalent `flutter build apk --debug`
from the `setu_app/` root, which wraps the same Gradle invocation) is the
step that would actually compile `PacketRelayEngine.kt`,
`SignatureVerifier.kt`, `MeshForegroundService.kt`, and everything else
under `setu_app/android/app/src/main/kotlin/com/setu/` — this has not
happened in this engagement at all, across all four sprints.

### Native unit tests specifically
```bash
cd setu_app/android
./gradlew testDebugUnitTest  # runs setu_app/android/app/src/test/kotlin/**, incl. PacketRelayEngineTest.kt
```
See `docs/mesh/NATIVE_TEST_INFRASTRUCTURE.md` for exactly what has and
hasn't been executed regarding these tests in this sandbox.

## 2. `Backend/` — FastAPI backend

### Requirements
- Python 3.x (check `Backend/requirements.txt` or an equivalent for the
  exact pinned version once one exists — not otherwise assumed here).
- `pip install -r requirements.txt` (network access to PyPI).

### Commands
```bash
cd Backend
pip install -r requirements.txt
# the exact run command (uvicorn entrypoint, etc.) depends on this
# service's actual structure -- not re-derived here since backend/AI
# changes are explicitly out of scope for this mesh/security sprint
# (see the Sprint 4 "no feature creep" rule); a backend-focused sprint
# should fill this in from that service's own entrypoint.
```

## 3. `setu_dashboard/` — React dashboard

### Requirements
- Node.js + npm/yarn (network access to the npm registry).

### Commands
```bash
cd setu_dashboard
npm install
npm run build   # or the project's actual configured script name
```

## 4. `setu_ai_service/`

Not touched by this sprint (explicitly out of scope per the "no feature
creep" rule) — its own build requirements are not re-derived here.

## 5. Confirmed blockers in THIS sandbox (as of Sprint 4, Sep 21 2026)

Stated precisely, with how each was confirmed — not assumed:

| Blocker | How confirmed | Sprint first found |
|---|---|---|
| No Flutter SDK anywhere in this sandbox | Direct filesystem search, `flutter` not on PATH | Sprint 2 |
| No Dart SDK anywhere in this sandbox | Direct filesystem search, `dart` not on PATH | Sprint 2 |
| No Android SDK anywhere in this sandbox | Direct filesystem search for `platforms/android-*`, `build-tools/`, etc. — none found | Sprint 2 |
| `setu_app/android/gradlew` blocked | Distribution download from `services.gradle.org` returns 403 through this sandbox's proxy | Sprint 2 |
| A local standalone Gradle 8.14.3 exists (`/opt/gradle/bin/gradle`) but still can't build this project | `local.properties`'s `flutter.sdk` path (`/home/vaibhav/snap/flutter/...`) doesn't exist here, and there's no Android SDK regardless | Sprint 3 |
| Maven Central (`repo1.maven.org`) network-blocked | Direct `curl` test, 403 on the CONNECT tunnel | Sprint 3, re-confirmed Sprint 4 |
| `org.json:json` (standalone Maven artifact) not locally cached anywhere | Exhaustive `find` across the filesystem, including Gradle's own bundled jars and the OS Maven repo | Sprint 4 |
| BouncyCastle (`bcprov-1.77.jar`) IS locally available via the OS's Debian package repo | Found and actually used — see `docs/security/NATIVE_SIGNATURE_TEST_VECTOR.md` | Sprint 4 |
| `kotlinc` IS invocable (bundled inside the local Gradle install's jars, not as an installed binary) | Actually invoked, compiled and ran a real test — see `docs/mesh/NATIVE_TEST_INFRASTRUCTURE.md` | Sprint 4 |
| JUnit 4.13.2 IS locally available (bundled with the same Gradle install) | Actually invoked as a real test runner, real output captured | Sprint 4 |

The pattern across sprints: **do not assume "network blocked" means
"everything blocked"** — several individual pieces (BouncyCastle,
`kotlinc`, JUnit) turned out to be present via the OS package manager or
bundled inside an unrelated tool (Gradle's own internals), each only found
by actually checking rather than extrapolating from the Maven Central
block. `org.json` and a real Android SDK are the two pieces that were
checked for just as thoroughly and genuinely are not present.

## 6. What "build validation" means for this repo right now

No sprint in this engagement has produced a real, compiled, running SETU
Android build. What has been produced instead, and should not be
confused with a real build pass:
- Manual brace/paren/bracket balance checks on every Kotlin file touched
  (a syntax sanity check, not a compile).
- Standalone, non-Gradle `javac`/`kotlinc` compilation of the small subset
  of files/logic with no Android or missing-dependency requirements (see
  `docs/mesh/NATIVE_TEST_INFRASTRUCTURE.md`).
- Careful manual review of every diff against the frozen wire-format
  contracts and existing architecture.

A real `./gradlew assembleDebug` (or `flutter build apk`) pass, on a
machine or CI runner with the actual toolchain, is the next concrete step
before any of this can be considered build-verified rather than
review-verified.
