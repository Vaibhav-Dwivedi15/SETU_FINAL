# SETU Mesh — Multi-Device Test Plan

Owner: Vib (Mesh/Architecture). Written Sep 21 2026.

**This is a plan, not a built test harness.** `NATIVE_MESH_AUDIT.md` §18
confirms there is no Android test infrastructure (`test/`/`androidTest/`,
zero `*Test*.kt` files, no test dependencies in `build.gradle.kts`) and no
physical devices or Android toolchain are available to this sandbox
session at all — so nothing below has been executed. This document exists
so that whoever next has real hardware (Vib, or anyone else on the team)
can run these scenarios without having to design them from scratch, and so
the current "we believe this works because the source reads correctly" gap
is explicit rather than silently assumed. Per the sprint brief: **build a
plan, not a simulator.**

## Prerequisites

- 4 physical Android devices, each with the SETU app installed from the
  same build (this build, once `feature/vib-native-mesh` merges and an APK
  is produced — see "Build Validation" in the final report for why no APK
  could be built in this sandbox).
- Devices should be spread across a physical area large enough that not
  every device is in direct BLE/Wi-Fi Direct range of every other device —
  the whole point of these scenarios is exercising *relay*, not direct
  connections. A large house, an office floor, or several rooms works;
  outdoor line-of-sight at 50-100m gaps is even more representative of the
  disaster-response use case.
- A way to independently observe each device's state during the test: the
  in-app history/recovery screens are sufficient (no special debug build
  needed), plus `adb logcat` filtered to the app's tag if a laptop is
  available for deeper native-log visibility.
- One device (or a laptop acting as the backend) reachable at the
  `BackendService` base URL, so "internet available" is a controllable
  variable rather than whatever cell/Wi-Fi happens to be present.

## Scenario 1 — Baseline 3-hop relay to backend and back

**Topology**: A ↔ B ↔ C, where A and C are NOT in direct range of each
other (verify this first — move them apart until Nearby Connections stops
showing a direct connection attempt between A and C). B is in range of
both. Only C has real internet; A and B do not (airplane mode, or simply a
location with no signal).

**Steps**:
1. On A, trigger an SOS (or any `EmergencyPacket`-originating action).
2. Observe B: the packet should appear in B's relay log / native logcat as
   received-and-relayed within a few seconds (subject to B's current duty
   cycle — see `NATIVE_MESH_AUDIT.md` §1 for the discoverability window).
3. Observe C: the packet should arrive via B, and since C has internet,
   `_tryUpload()` should succeed and C should originate an `AckPacket`.
4. Observe the ack traveling back: C → B → A.
5. On A, confirm the emergency's status transitions from "Sent" to
   "Delivered" in the history screen.

**Pass criteria**: A shows "Delivered" within a reasonable window (record
actual elapsed time — this doubles as a real-world latency data point for
the Performance Baseline in the final report, since none exist yet).

**What this validates**: the full path this codebase's source review
claims works — multi-hop relay, native TTL/dedup, exit-node upload, ack
origination, ack relay back, Dart-side status update via
`MeshLocator.acknowledgments` — end to end, for the first time on real
hardware in this project's life as far as this audit can determine.

## Scenario 2 — Exit node loses internet mid-relay

Same topology as Scenario 1, but turn C's internet OFF partway through (or
start the scenario with C offline and only bring it online after A's
packet has already reached B). 

**Steps**: same as Scenario 1, except toggle C's connectivity at the point
described above.

**Pass criteria**: the packet does not get lost — it should sit queued at
whichever device currently holds it (B or C) and successfully upload once
C's connectivity returns, via `_retryPendingUploads()`'s 30-second timer.
A should still eventually see "Delivered," just later.

**What this validates**: `LocalQueueService` durability and the
retry-path ack fix from Bulk Sprint 1 (`_retryPendingUploads()` now calls
`_markPacketDelivered()` → `_originateAck()`, previously it did not) — this
is the first real-hardware exercise of that specific fix.

## Scenario 3 — Mid-relay disconnect (B drops out)

Same topology as Scenario 1. After A originates but before B relays to C,
force B to disconnect from both A and C (airplane-mode toggle on B, or
physically move it out of range of both).

**Steps**:
1. A originates.
2. Before observable relay to C, disconnect B from the mesh entirely.
3. Bring B back into range/online after a delay (30s-2min).
4. Observe whether the packet still reaches C once B reconnects (it should
   still be in B's — or A's, if B never received it before disconnecting —
   local queue) or whether A needs to be in range of C directly by then.

**Pass criteria**: no crash on any device during the disconnect; the
packet is not silently lost — it either reaches C once B reconnects, or
(if the test is set up so A comes into direct range of C instead) reaches
C that way. Either is an acceptable pass; a genuinely lost packet with no
device ever showing an error/drop log is not.

**What this validates**: `onDisconnected` cleanup in
`NearbyConnectionsManager` (§11 of `NATIVE_MESH_AUDIT.md`, confirmed
correct from source) actually holds up under a real mid-transfer
disconnect, not just an idle one — and that the relay queue doesn't get
stuck waiting on a peer that's gone.

## Scenario 4 — 4-device loop topology (relay-loop protection)

**Topology**: A ↔ B ↔ C ↔ D ↔ A (a ring — each device only in direct
range of its two neighbors, not the opposite corner). This is the
topology most likely to expose a relay loop if dedup/TTL protection is
broken, since a packet can legitimately go around the ring more than once
without a working dedup cache.

**Steps**:
1. On A, originate a packet.
2. Let it propagate around the ring in both directions simultaneously
   (B and D both receive it directly from A and both attempt to relay
   toward C).
3. Watch each device's relay log / native logcat for repeated relay of the
   *same* `packet_id`.

**Pass criteria**: each device relays the same `packet_id` at most once
(the native `seen` cache, now thread-safety-fixed this sprint, should
reject the second copy each device receives from the opposite direction).
No device should show the packet bouncing back and forth. TTL should hit
zero and stop propagation even in a pathological case where dedup somehow
missed a copy — this scenario is explicitly designed to stress both
protections at once, since a real deployment topology (a disaster
response perimeter, a building's floors) is far more likely to have loops
than the simple chain in Scenario 1.

**Pass criteria (secondary)**: no ANR, no crash, no device becoming
unresponsive under the resulting burst of near-simultaneous relay
attempts from two directions — this is also the first real exercise of
this sprint's thread-safety fix to `PacketRelayEngine.process()` under
genuine concurrent Nearby Connections callback delivery (Scenarios 1-3
are unlikely to produce truly concurrent calls; this one is designed to).

## What These Scenarios Do NOT Cover

- Battery-tier behavior differences (would need devices actually at
  different battery levels, or `BatteryService` mocked — out of scope for
  a first hardware pass; note actual behavior observed and compare against
  `FAILURE_HANDLING.md`'s documented thresholds as a secondary observation
  if convenient, not a blocking pass criterion).
- Signature/replay attack scenarios (would require a modified/malicious
  client sending crafted packets — a security-test exercise, not a
  reliability one; tracked separately, not part of this plan).
- Scale beyond 4 devices — worth doing once these 4 pass, but 4 is enough
  to exercise every relay/loop/exit-node/disconnect behavior described in
  this codebase's design.

## Recording Results

For whoever runs this: capture, per scenario, at minimum — pass/fail,
elapsed time from origination to "Delivered," and any logcat lines showing
an unexpected repeated relay, crash, or ANR. This data is exactly what
`SETU_VIB_NATIVE_MESH_FINAL_REPORT.md`'s "Real-Device Results" section
needs and currently cannot contain, because no hardware was available to
this sandbox session.

## Sprint 4 addition — Compact Operator Checklist (14 scenarios)

Sep 21 2026 (Vib, Bulk Sprint 4, §18/§33). Scenarios 1-4 above are
detailed, narrative walkthroughs — good for a first careful run, but
slow to repeat. This section is the same underlying test surface
condensed into a single table an operator can work through quickly on a
real 4-device pass (or a smaller subset with fewer devices — most rows
only need 2-3), still with nothing executed, since no hardware exists in
this sandbox — same disclaimer as every other line in this document.

**Roles** (fixed for the whole checklist, matches Scenarios 1-4's
topology):
- **Device A — Originator.** Always the device that triggers the
  SOS/emergency packet. Never relays anyone else's packet in these
  scenarios (kept simple on purpose — a real deployment has no fixed
  roles, but a fixed role per device makes results comparable run to
  run).
- **Device B — Relay.** First hop. Not in direct range of C (verify
  before starting, exactly as Scenario 1 says).
- **Device C — Exit Node.** Has real internet connectivity (the other
  three devices should not, so "reached the backend" only happens through
  C).
- **Device D — optional loop participant.** Only needed for the ring
  scenarios (#4, #13 below); can be left out of a 3-device pass, with
  those two rows marked "not run — no Device D" rather than skipped
  silently.

**Per-row fields to record** (columns for the table below): Timestamp,
Device(s) involved, Android version, Battery % at start, Topology note
(any deviation from the fixed A/B/C/D roles above), Result
(PASS/FAIL/BLOCKED), Latency (origination → "Delivered", if applicable),
Logs (any logcat line worth keeping — crash, ANR, unexpected repeated
relay, signature rejection).

| # | Scenario | Devices | What to do | Pass criteria |
|---|---|---|---|---|
| 1 | Single-hop (direct) | A, C | Put A in direct range of C only (no B). A originates. | C receives directly, uploads, acks; A shows "Delivered". |
| 2 | Two-hop relay | A, B, C | Scenario 1 above (this file's main §"Scenario 1"). | A shows "Delivered" via B→C round trip. |
| 3 | Three-hop relay | A, B, C, D (chain, not ring: A↔B↔C↔D, D also has internet or forwards to C) | Chain topology, A originates, D or C is the only exit node. | Packet reaches the exit node and acks back across all 3 hops. |
| 4 | Four-device ring (loop protection) | A, B, C, D | This file's Scenario 4. | No device relays the same `packet_id` more than once; no ANR/crash. |
| 5 | Mid-relay disconnect | A, B, C | This file's Scenario 3. | Packet not silently lost; reaches C once B reconnects or A comes into direct range. |
| 6 | Exit-node internet loss | A, B, C | This file's Scenario 2. | Packet queues and uploads once C's connectivity returns; A eventually shows "Delivered". |
| 7 | Internet restoration mid-queue | B or C | Start with NO device having internet; originate; bring C online after a delay. | Same as #6, from a colder start (nobody had connectivity at origination time). |
| 8 | Duplicate packet (dedup) | A, B | A originates; immediately re-send the exact same packet_id a second time (e.g. via app restart replay, or a debug hook if one exists) to B. | B's `duplicatesFiltered` counter increments; the packet is not relayed twice. |
| 9 | Invalid signature (Sprint 4, NEW) | A (modified client or hand-crafted packet), B | Send B a packet with a tampered/invalid `signature` field (needs a way to inject a malformed packet — a debug/test hook, since the real app always signs correctly; document however this was actually done on the day). | B's `signatureFailures` counter increments; packet is neither relayed nor added to B's dedup cache (a subsequent valid copy of the same packet_id should still be accepted — see `PacketRelayEngineTest.kt`'s `process_invalidSignature_isNotAdmittedToDedupCache` for the same assertion at the unit level). |
| 10 | App restart (START_STICKY persistence) | Any one device (B recommended, mid-relay) | Force-stop the app process on B while it has active dedup state; let `START_STICKY` restart the service; re-send a packet B had already seen before the restart. | B does NOT re-relay a packet it had already relayed before the restart (persisted `seen` cache survived) — see `MeshStateStore`/`SPRINT4_EDGE_CASE_REVIEW.md` §1. |
| 11 | Bluetooth OFF/ON | Any one device (B recommended) | Toggle Bluetooth off, wait, toggle back on. | Mesh resumes advertising/discovery automatically without restarting the app — see `SPRINT4_EDGE_CASE_REVIEW.md` §2. |
| 12 | Wi-Fi OFF/ON | Any one device | Same as #11, for Wi-Fi. | Same pass criteria as #11. |
| 13 | Low battery / power-saver duty cycle | Any one device, genuinely low battery or simulated via `updateMeshPolicy` | Trigger the power-saver tier; confirm the device is still discoverable, just on a longer duty-cycle interval. | Packets still relay, with acceptable (documented, not zero) added latency — not a hard pass/fail number, a recorded observation. |
| 14 | Recovery ACK round trip | A, C | After Scenario 1/2 succeeds and C's `AckPacket` returns to A, confirm the emergency's full lifecycle status (not just "Delivered", but any Recovery/responder-facing state the app exposes) updates correctly. | A's history screen reflects the correct terminal state, matching what `ACK_LIFECYCLE.md` documents. |

Rows 9-13 are new to this sprint (signature verification, START_STICKY
persistence, and radio-resume did not exist before Sprint 3/4); rows 1-8
and 14 restate this file's original four narrative scenarios plus two
additional decompositions (single-hop and internet-restoration-from-cold)
in the same compact format for faster repeat runs.
