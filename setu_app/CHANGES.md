# SETU mobile app — mesh features (Aug 4 2026, v2)

Drop each file into your existing `setu_app` project at the exact same
relative path. 12 new files, 4 edits to existing files. File-by-file
destination table is at the bottom for a quick copy-paste pass.

**Not tested against a real device or emulator** — this sandbox has no
network access to pub.dev, so `flutter pub get` / `flutter analyze` /
`flutter test` / `flutter build` could not be run. Written carefully
against the actual existing code (real imports, real design-system API
names, real packet model pattern, real method-channel names) but run
`flutter analyze` and a real build before trusting it for a demo.

---

## 🔴 The most important fix in this batch

**`SosRepository.triggerSOS()` never called the mesh layer at all.**
Found while wiring the ack packet in. The entire mesh stack — signing,
relay, TTL, dedup, native transport — is real and works, but the SOS
button only ever sent SMS and wrote a local `SharedPreferences` mock
entry. Pressing SOS with no signal did **not** put anything on the mesh.
This is now fixed: `triggerSOS()` builds a signed `EmergencyPacket` via
the existing `EmergencyPacketBuilder` and calls
`MeshLocator.instance.meshService.originate()`, for every SOS regardless
of alert mode. This is the single highest-priority thing to verify on a
real device before anything else in this batch.

---

## What's fully wired and ready

1. **Login permission gate** — `mesh_permission_service.dart` +
   `permission_gate_screen.dart` + `app_router.dart` redirect. No new
   package (`permission_handler` was already a dependency, unused).
2. **Permission retry before SOS** — `sos_repository.dart` re-checks and
   re-requests before doing anything else.
3. **The mesh origination fix above** — `sos_repository.dart` +
   `emergency_packet_builder.dart` (unchanged, just now actually called)
   + `mesh_locator.dart` (unchanged, just now actually used from the SOS
   flow instead of only from `home_screen.dart`'s dev/test screen).
4. **Location-aware relay re-entry** — `PacketRelayEngine.kt` tracks
   per-packet last-seen location (haversine, 150m threshold) and allows
   re-relay if a device has moved. `sos_repository.dart` now also pushes
   a location update to the native side (`updateLocation` channel call)
   right after every SOS's GPS fetch — the cheap wiring point suggested
   in the previous version of this changelog.
5. **Ack packet, fully wired end-to-end this time** — `ack_packet.dart`,
   `ack_packet_builder.dart`, and `mesh_service.dart`:
   - Whichever device successfully uploads an `EmergencyPacket` to the
     backend (the real exit node, "Pn") automatically originates a
     signed `AckPacket` back into the mesh.
   - Any device relays it like any other packet.
   - The device whose `emergencyId` it matches (tracked via a new
     `_originatedEmergencyIds` set, populated in `originate()`) surfaces
     it on a new `MeshService.acknowledgments` stream instead of
     silently relaying it onward.
   - Ack/Alert packets are explicitly excluded from `_tryUpload` — the
     backend's `/ingest` schema doesn't understand these two types, so
     they stay mesh-only by design (see point 6).
6. **Community alert packet, fully wired end-to-end this time** —
   `alert_packet.dart`, `alert_packet_builder.dart`, and
   `sos_repository.dart`: a real signed `AlertPacket` now goes out over
   the mesh whenever `alertMode == AlertMode.public`, alongside the
   existing local `NearbyRepository` entry (which only ever wrote to
   this device's own `SharedPreferences` and was never visible to
   anyone else — kept as-is, the mesh broadcast is additive).
7. **Connectivity-based mesh start/stop** — `connectivity_mesh_controller.dart`
   + small `MeshChannelHandler.kt` / `MeshForegroundService.kt` additions
   (`startMesh`/`stopMesh`/`updateLocation` channel methods, none of
   which existed before). **Now actually called** — `main.dart` invokes
   `ConnectivityMeshController.instance.enableAutoMode()` on startup.

## What's still genuinely open (honest gaps, not fixed here)

1. **A's delivery status is still optimistic.** `sos_repository.dart`'s
   `status` string is still set to `"Delivered"` the instant the packet
   is handed off, not once an ack actually confirms it. Left alone
   deliberately this round — `history_screen.dart`'s
   `_isSuccessStatus()` does an exact string match on `"delivered"` for
   its green/red styling, so renaming the status without also updating
   that check would silently break the history screen. Fixing this
   properly means: `HistoryRepository` gaining an update-by-emergencyId
   method, `MeshServiceImpl.acknowledgments` feeding it, and
   `_isSuccessStatus()` being updated to match — three files, one
   coordinated change, not something to half-do in a drop-in patch.
2. **`community_demo_screen.dart` still shows `mockAlert`, not real
   incoming `AlertPacket`s.** The packets now actually go out over the
   mesh (see point 6 above) — nothing yet consumes
   `MeshService.incomingPackets` and filters for `AlertPacket` to
   display them. That's a UI-only task now, not a plumbing one.
3. **Ack/Alert packets never reach the backend or dashboard**, by
   design (see point 5) — if the team later wants responders to *see*
   "packet confirmed reached device X hops away" on the dashboard, that
   needs a real backend schema change (new packet types in `PacketIn`,
   `ingest.py`), not just a mobile-side fix.
4. **Push-notification-based community alerts** (reaching SETU users
   outside current mesh range) still needs `firebase_messaging` or
   similar — genuinely out of scope for a mesh-only broadcast, flagged
   here again since it came up in the original ideation.

---

## File destination table

| File | Type | Destination in your project |
|---|---|---|
| `mesh_permission_service.dart` | new | `lib/features/onboarding/data/services/` |
| `permission_gate_screen.dart` | new | `lib/features/onboarding/presentation/screens/` |
| `ack_packet_builder.dart` | new | `lib/features/sos/data/services/` |
| `alert_packet_builder.dart` | new | `lib/features/sos/data/services/` |
| `connectivity_mesh_controller.dart` | new | `lib/core/services/` |
| `ack_packet.dart` | new | `lib/mesh/models/` |
| `alert_packet.dart` | new | `lib/mesh/models/` |
| `app_router.dart` | edit | `lib/routes/` (overwrite) |
| `sos_repository.dart` | edit | `lib/features/sos/data/repositories/` (overwrite) |
| `packet_type.dart` | edit | `lib/mesh/enums/` (overwrite) |
| `packet_factory.dart` | edit | `lib/mesh/models/` (overwrite) |
| `mesh_service.dart` | edit | `lib/mesh/services/` (overwrite) |
| `main.dart` | edit | `lib/` (overwrite) |
| `MeshChannelHandler.kt` | edit | `android/app/src/main/kotlin/com/setu/setu_app/handlers/` (overwrite) |
| `MeshForegroundService.kt` | edit | `android/app/src/main/kotlin/com/setu/mesh/` (overwrite) |
| `PacketRelayEngine.kt` | edit | `android/app/src/main/kotlin/com/setu/mesh/` (overwrite) |

Everything else in your project (emergency_packet_builder.dart, mesh_locator.dart,
identity_service.dart, signing_service.dart, etc.) is unchanged — this
batch only newly *calls* those, it doesn't modify them.

## After dropping the files in

1. `flutter pub get` (no new packages added, but safe to re-run)
2. `flutter analyze` — catch anything the sandbox couldn't verify
3. Real-device test, in order:
   a. Fresh install → confirm the permission gate screen appears and
      granting permissions gets you to home
   b. Trigger a private SOS with Wi-Fi/data OFF, a second device nearby
      with the app running → confirm the second device's app logs show
      a received `EmergencyPacket` (this is the actual end-to-end relay
      test the project has never completed — see the separate test plan)
   c. Trigger a public SOS → confirm an `AlertPacket` also goes out
      (check logs; no UI consumes it yet, see gap 2 above)
