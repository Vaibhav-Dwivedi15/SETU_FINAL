# SETU — Developer Reference Notes

> Practical onboarding/reference doc for anyone working in this repo. For the project *pitch and concept*, see `Notes.md`. For judge-facing content, see the `notes/` folder. This file is about the actual codebase.

---

## Project Structure (actual, as of last `tree` check)

```text
setu_app/
├── android/
│   └── app/src/main/kotlin/com/setu/mesh/
│       ├── NearbyConnectionsManager.kt
│       ├── MeshForegroundService.kt
│       └── PacketRelayEngine.kt
├── lib/
│   ├── core/                    (constants/routes/theme — scaffolded, not yet filled)
│   ├── main.dart
│   ├── mesh/
│   │   ├── enums/                (emergency_priority.dart, packet_type.dart)
│   │   ├── models/                (mesh_packet.dart, emergency_packet.dart,
│   │   │                           termination_packet.dart, packet_factory.dart,
│   │   │                           device.dart, mesh_node.dart)
│   │   └── services/               (mesh_service.dart, nearby_service.dart,
│   │                                local_queue_service.dart, signing_service.dart,
│   │                                responder_registry.dart, mesh_constants.dart, ...)
│   ├── screens/
│   │   ├── home/home_screen.dart   (only screen that exists so far)
│   │   └── splash/                  (empty — Sudheer's territory)
│   ├── security/                    (nonce_cache.dart, packet_validator.dart,
│   │                                 replay_protection_service.dart,
│   │                                 security_constants.dart, security_exceptions.dart,
│   │                                 timestamp_validator.dart)
│   ├── services/                    (backend_service.dart, battery_service.dart,
│   │                                 power_mode.dart, power_mode_controller.dart)
│   ├── utils/
│   └── widgets/
├── test/                            (packet_test.dart, cache_and_relay_test.dart)
├── notes/                           (judge-facing corrected reference docs)
├── docs/archive/                    (Notes.md, Notes1.md — superseded planning drafts)
├── pubspec.yaml
└── README.md
```

---

## Important Files, What They Actually Do

### `pubspec.yaml` ⭐
Flutter project's main config — dependencies, assets, SDK version constraints. Touch this when adding a package; run `flutter pub get` after.

### `lib/mesh/models/mesh_packet.dart`
Base packet class. **snake_case JSON keys** (`packet_id`, `sender_id`, `hop_count`, etc.) — this is the frozen wire format everyone (backend, AI service, dashboard) must match. `EmergencyPacket` and `TerminationPacket` extend it. `withRelayHop()` is the method that decrements TTL / increments hop_count for forwarding — covered by unit tests.

### `lib/mesh/services/mesh_service.dart`
The core orchestrator: `originate()` sends your own packet, `_handlePayload()` receives/validates/verifies an incoming one, `_relayPacket()` forwards it onward (battery-gated via `MeshPolicy.allowRelay`), `_tryUpload()` pushes to backend when internet is available.

### `lib/mesh/services/mesh_policy.dart`
Derives relay/upload permissions from `PowerMode` (full/balanced/powerSaver). Below 20% battery → `powerSaver` → `allowRelay: false`. Note: this only gates relaying *other devices'* traffic — your own SOS always sends regardless of battery (`originate()` never checks this policy).

### `lib/security/*`
Shaurya's module, integrated by Vaibhav. `PacketValidator` is the single entry point — checks packet version, TTL bounds, timestamp freshness, and nonce replay, all in one call. Runs once, at intake, not again at upload time (a delayed store-and-forward packet shouldn't get penalized for being old).

### `lib/mesh/services/responder_registry.dart`
MVP-level termination authorization. Fails **open** (allows termination through with a logged warning) if no backend registry has synced yet — intentional so termination isn't blocked entirely while the real backend piece is built, but flagged clearly as not-yet-secure.

### `android/app/src/main/kotlin/com/setu/mesh/PacketRelayEngine.kt`
Native-side relay dedup/TTL logic — keeps working even when the Dart engine isn't attached (app backgrounded/killed). **Was previously broken** due to a camelCase/snake_case field mismatch (`packetId` vs the real `packet_id`); fixed.

---

## Environment

- **Vaibhav (Team Lead) — Ubuntu.** Bash commands.
- **Everyone else — Windows.** PowerShell/cmd commands.
- See `SETU_Working_Style.md` (pasted in every chat) for the exact command set per OS.

## Common Commands (Ubuntu)

```bash
cd ~/setu_app
flutter pub get              # fetch dependencies
flutter test                 # run unit tests (currently 14, all passing)
flutter clean                # nuke build cache if Gradle errors appear (e.g. stale FontManifest.json)
flutter devices              # confirm connected devices are recognized
flutter run -d <device_id>   # run on a specific physical device
adb devices -l                # list connected Android devices
adb -s <device_id> logcat | grep MeshService   # live relay/packet logs for one device
```

## Known Gaps (tracked, not hidden — see also `Notes.md` Part 7.3)

1. Multi-hop (3+ device) relay — untested, need a 3rd physical device.
2. Termination-packet authorization — needs backend registry sync (Ayush + Shaurya).
3. Native security-module (`SigningService` etc.) — unit test coverage unconfirmed.
4. Mobile UI screens (`sos_trigger_screen.dart`, `stealth_mode_screen.dart`, `relay_status_screen.dart`) — not yet in this repo, Sudheer's track.
5. AI service (`setu_ai_service`) ↔ backend `/ingest` integration — not yet confirmed wired together.

## Where Authoritative Docs Live

- **Judge-facing / pitch content:** `notes/` folder (`Judge_QA.md`, `Security_Architecture.md`, `Mesh_Protocol.md`, `System_Architecture.md`, `System_Architecture_Diagram.md`, `Problem_Statement.md`, `Unique_Value_Proposition.md`) — these are the corrected, honest versions. Trust these over anything in `docs/archive/`.
- **Full planning narrative:** `Notes.md` (this folder) — v2.0, corrected.
- **This file:** practical dev reference, updated as the codebase changes.
