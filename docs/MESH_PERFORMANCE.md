# SETU Mesh Performance

Status as of this engineering session. Follows the session rule: **only measured values are reported; everything else says NOT MEASURED, never a placeholder number.**

## Why this document is mostly "NOT MEASURED"

This session ran in a cloud container with no Android device, no emulator, and no Flutter/Dart SDK (the SDK download was blocked by the sandbox's egress proxy — confirmed with an HTTP 403 on the standard Dart SDK archive URL). Real mesh performance — discovery time, connection establishment, over-the-air hop latency — can only be measured on physical Android hardware running the actual `NearbyConnectionsManager` / `PacketRelayEngine` / `MeshForegroundService` code over real Bluetooth/Wi-Fi Direct. That did not happen in this session. Numbers below are marked accordingly.

What *was* verified in this session: the algorithm correctness of the new priority queue and adaptive TTL logic (ported to Python and run against 27 assertions — see `scratchpad/verify_logic.py` in the session record, not part of the repo), and the shape of a multi-device correctness test harness (`test/mesh_simulation.dart`, `test/mesh_harness_test.dart`) that exercises `MeshServiceImpl` end-to-end over a simulated transport. Neither of these produces a timing number that belongs in a performance table — see the scope note below.

## Test setup

| | |
|---|---|
| Device count | NOT MEASURED — no physical devices available this session |
| Topology | NOT MEASURED |
| Packet type | NOT MEASURED |
| Packet count | NOT MEASURED |
| Radio | Android Nearby Connections, `Strategy.P2P_CLUSTER` (unchanged this session) |

## Measured latency

| Stage | Before | After | Notes |
|---|---|---|---|
| Discovery time | NOT MEASURED | NOT MEASURED | Instrumented this session (`NearbyConnectionsManager.discoveryLatencyMicros`), never run on a device |
| Connection establishment | NOT MEASURED | NOT MEASURED | Instrumented this session (`connectionLatencyMicros`), never run |
| Single-hop delivery | NOT MEASURED | NOT MEASURED | |
| Multi-hop delivery | NOT MEASURED | NOT MEASURED | |
| End-to-end delivery (origin timestamp → backend upload) | NOT MEASURED | NOT MEASURED | Instrumented (`MeshMetrics.endToEnd`), reuses the packet's existing wire timestamp, never run against real traffic |
| Packet loss | NOT MEASURED | NOT MEASURED | Needs a multi-device physical run; a single device cannot observe what it never received |
| Duplicate rate | NOT MEASURED | NOT MEASURED | Instrumented (`PacketRelayEngine.duplicatesFiltered` / `totalProcessed`), never run |
| Relay success rate | NOT MEASURED | NOT MEASURED | Instrumented (`MeshMetrics.relaySuccessRate`) — caveat: this measures "handed to the radio", not confirmed peer receipt (Nearby Connections' `sendPayload` gives no per-peer delivery confirmation) |
| Queue wait, by priority tier | NOT MEASURED | NOT MEASURED | Instrumented (`MeshMetrics.queueWaitByPriority`); this is the number that would actually demonstrate "critical never waits behind routine traffic" once measured |
| Battery delta | NOT MEASURED | NOT MEASURED | Instrumented (`MeshMetrics.batteryDelta`), needs a long real-device session with a defined workload to mean anything |

"Before" is blank rather than the old flat-TTL/no-priority behavior's numbers because those were never benchmarked either — the audit found the same gap. There is no earlier baseline to compare against; this session's job was to build the instrumentation that makes a first baseline possible, not to invent one.

## What correctness testing *did* establish (not a substitute for the table above)

- `AdaptiveTtl.nextTtl` and `PriorityRelayQueue` satisfy their stated invariants under 27 direct assertions (TTL never exceeds `maxTTL`, never grows, always terminates; CRITICAL packets are never delayed behind a lower tier; no tier starves forever, capped so aging can never reach CRITICAL; the queue never exceeds its bound and sheds lowest-priority-oldest first).
- `test/mesh_harness_test.dart` exercises `MeshServiceImpl` over a simulated in-process transport across 1/2/3/5/10-device chains, dense and sparse topologies, disconnect-during-relay, duplicate/expired/replayed/unsigned packets, concurrent SOS, termination handling, and backend/connectivity failure modes. All of it runs through real `MeshServiceImpl`, `PriorityRelayQueue`, and `AdaptiveTtl` code — but the transport is a function call, not a radio, so **no timing from that harness may be reported as mesh latency**. It proves the logic is correct; it does not prove the logic is fast.
- Neither of the above was actually executed against the Dart toolchain in this session (no SDK available — see above). The Python port of the two pure-logic algorithms was executed and all 27 assertions passed; the Dart test files themselves are unverified to compile until `flutter test` runs on a machine with the SDK.

## Failures observed

NOT MEASURED — no execution occurred against real infrastructure.

## Duplicates observed

NOT MEASURED.

## Limitations

1. No physical Android device or emulator was available in this session — this is the primary limitation and the reason almost every row above reads NOT MEASURED.
2. The Flutter/Dart SDK could not be installed (sandboxed egress proxy returned 403 on the SDK download), so even `flutter analyze` / `flutter test` — which need no device — could not confirm the new/changed Dart files compile.
3. The native Kotlin changes (`PacketRelayEngine`, `NearbyConnectionsManager`, `MeshForegroundService`, `MeshChannelHandler`) were not compiled or run; they were reviewed by hand for correctness and consistency with the existing patterns in the file, mirroring the Dart-side `AdaptiveTtl` logic line-for-line, but a Gradle build was not attempted.
4. Relay success rate and packet-loss figures, once measured, will need the caveat stated in the table: Nearby Connections' `sendPayload` does not confirm per-peer delivery, so "relay success" measures hand-off to the radio, not confirmed receipt. True delivery confirmation needs `AckPacket` round-trip data or the physical multi-device harness.

## Next step to close this gap

Run `flutter analyze` and `flutter test` on a machine with the Flutter SDK installed to confirm this session's Dart changes compile and the new test files pass. Then run the app on 2–3 physical Android devices with the debug metrics screen (which should read `MeshMetrics.report()` — not yet wired to a screen this session, see Remaining Work in the final report) to get the first real discovery/connection/end-to-end numbers. Only once that baseline exists does a "before vs. after" comparison mean anything for the SIH presentation.
