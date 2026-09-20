# SETU — end-to-end mesh relay test plan
**Purpose:** close the single most important unresolved item in this project — a full signed-packet relay between two physical devices has never been observed. Connection layer (BLE/Wi-Fi Direct handshake) is confirmed; actual packet relay with signature verification, end to end, has not. This plan is designed to close that gap in stages, so a failure at any stage tells you exactly where the problem is instead of "it didn't work."

**Do this before a demo, not during one.** Budget at least one full afternoon — first attempts at real BLE/Wi-Fi Direct testing almost always surface OS-specific permission or battery-optimization issues that eat time.

---

## What you need
- 3 Android phones minimum (2 is the bare minimum for a direct A→B test; 3 lets you test actual multi-hop A→B→C, which is the real claim being made)
- All 3 with the latest build from this session installed (mesh-features-v2 changes applied, `flutter pub get` + fresh build run)
- One phone with a working SIM/data plan (this will be your internet-connected exit node)
- The other 1-2 phones in airplane mode with Wi-Fi and Bluetooth manually re-enabled (airplane mode + BT/WiFi on = no cellular, no data, but mesh radios active — this is the actual "offline" condition the app is designed for)
- `adb logcat` running on each device (via USB or wireless debugging) so you can watch `MeshService` / `PacketRelayEngine` logs live, not guess from the UI alone

## Stage 0 — sanity checks (5 min, do this first)
- [ ] All 3 phones show the permission gate screen on fresh install, and granting permissions gets you to home (this is new as of today's changes — test it first since everything downstream depends on it)
- [ ] Each phone's notification shade shows "SETU active — protecting nearby devices" (confirms `MeshForegroundService` is actually running)
- [ ] `adb logcat -s MeshService` shows `Mesh started. Sender ID: ...` for each phone with a distinct ID

## Stage 1 — two-device direct relay (the test that's never been done)
Phone A (airplane mode, BLE+WiFi on) and Phone B (airplane mode, BLE+WiFi on), physically 1-2 meters apart.

- [ ] On A: trigger a private SOS
- [ ] On B's logcat, within a few seconds, confirm ALL of these lines appear, in this order:
  - `Raw payload received: N bytes`
  - `Decoded packet: <id> type=emergency ttl=... hop=0 sender=...`
  - `Packet passed PacketValidator: <id>`
  - `Packet signature VERIFIED: <id>` ← **this is the specific line that's never been confirmed on a real device before.** If you see "Dropped packet with invalid signature" instead, stop here — that's the actual gap, and it's a signing/verification bug, not a connectivity issue.
  - `Packet ACCEPTED and queued: <id>`
  - `Relayed packet to next hop: <id> ttl=... hop=1`
- [ ] Confirm B's own logcat does NOT show an upload attempt succeeding while B is still in airplane mode (it should log `hasRealInternet()` returning false and skip upload) — this confirms B is correctly behaving as a relay-only node, not accidentally getting internet from somewhere

**If this stage fails:** don't move to Stage 2. Everything after this assumes direct relay works. Common failure points to check, in order: (1) both phones actually granted all 5 permissions — check via `adb shell dumpsys package com.setu.setu_app | grep permission`, (2) BLE/Wi-Fi Direct actually connected — check for `Peer connected` in logcat before the SOS was even sent, (3) if peers never connect at all, it's almost always a missing `NEARBY_WIFI_DEVICES` or `BLUETOOTH_SCAN` grant on Android 12+, not a code bug.

## Stage 2 — multi-hop relay (A → B → C, no direct A-C range)
Phone A and Phone C positioned far enough apart that they're NOT in direct BLE/Wi-Fi Direct range of each other, with Phone B physically between them, in range of both.

- [ ] On A: trigger a private SOS
- [ ] On B's logcat: same sequence as Stage 1
- [ ] On C's logcat: confirm the packet arrives with `hop=1` (relayed by B, not `hop=0` which would mean C somehow got it directly from A)
- [ ] This is the test that actually proves "mesh," not just "two phones talking" — Stage 1 alone doesn't prove multi-hop works

## Stage 3 — exit node upload (C has real internet)
Phone C from Stage 2, but with airplane mode OFF (real data/Wi-Fi).

- [ ] Confirm C's logcat shows `hasRealInternet()` returning true, then `Uploaded packet <id>` from `BackendService`
- [ ] Check the responder dashboard (`https://setu-sih-dashboard.vercel.app`) — the incident should appear within a few seconds, with `hop_count: 2`
- [ ] Confirm C's logcat also shows `Ack originated for emergency: <id>` (new as of today's changes) — this is C signaling back into the mesh that the upload succeeded

## Stage 4 — ack reaches back to A (new as of today, not tested at all yet)
Continuation of Stage 3, same physical setup.

- [ ] On B's logcat: confirm the ack packet relays through (`type=ack`)
- [ ] On A's logcat: confirm `Ack received for own emergency: <id>` appears — this is the specific line that proves the real-confirmation loop works, as opposed to A's optimistic "Delivered" status that shows regardless
- [ ] Note: A's UI does NOT currently update to reflect this (see CHANGES.md gap #1) — this stage is a logcat-only check for now, not a visible UI confirmation, until that follow-up wiring is done

## Stage 5 — SMS + government path (should already work, verify anyway)
- [ ] Confirm emergency contacts on Phone A's contact list actually receive the SMS (real phone number, not a test number)
- [ ] Confirm the dashboard shows the incident with correct `incident_type`, priority, and location

## Stage 6 — dedup sanity check
- [ ] Send the same SOS twice in quick succession from A (or physically don't move B, C at all) — confirm the dashboard does NOT create two separate incidents for what should be one, matching the backend's dedup fix from earlier today
- [ ] This specifically needs a demo-condition dry run per the backend debug report — multiple SOS submissions, no backend restart in between, since the AI dedup's in-memory cluster state is process-lifetime-scoped

---

## What "done" looks like
Every checkbox above ticked, on real hardware, with logcat evidence saved (screenshots or copied log excerpts) — not just "it seemed to work." Given this closes the project's single most-flagged unresolved claim, keep the logcat evidence; it's exactly what should back up any pitch/documentation claim that end-to-end relay has been verified.
