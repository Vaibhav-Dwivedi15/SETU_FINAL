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
