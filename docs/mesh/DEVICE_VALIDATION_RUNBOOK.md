# SETU Mesh — Device Validation Runbook

Owner: Vib (Mesh/Architecture). Written Sep 21 2026, Bulk Sprint 5, Phase 11.

**No device testing has occurred anywhere in this engagement.** This is a
procedure for whoever runs the first real hardware pass — it is a plan,
not a report of results. It supersedes nothing in
`docs/mesh/MULTI_DEVICE_TEST_PLAN.md` (that file's 4 narrative scenarios
and Sprint 4's 14-row compact checklist remain valid); this runbook adds
the Sprint 5-specific scenarios (signature rejection, TTL exhaustion,
termination, forced restart interacting with the new security gate) in
the same concise, evidence-oriented format, and is the single place an
operator should start from for a Sprint 5+ hardware pass.

## Roles (same as `MULTI_DEVICE_TEST_PLAN.md`)

- **Device A — Originator.**
- **Device B — Relay.** Not in direct range of C.
- **Device C — Exit Node.** Has real internet.
- **Device D — optional loop/chain participant.** Needed for scenarios 3
  and 15 only; mark those "NOT RUN — no Device D" if unavailable.

## Required evidence per scenario

Every row below needs, at minimum: a timestamp, which device(s), Android
version + battery %, the exact setup, the exact action taken, the
expected result (already stated per row), the actual result, any relevant
logcat lines (`adb logcat | grep -i setu` or the app's actual log tag),
and a clear PASS/FAIL/BLOCKED verdict. "Looked fine" is not evidence — a
copied logcat line, an in-app screenshot of the history/status screen, or
an elapsed-time measurement is.

| # | Scenario | Setup | Action | Expected result | Logs to capture | Evidence required |
|---|---|---|---|---|---|---|
| 1 | Valid emergency packet | A↔B↔C chain, C has internet | A originates a real SOS through the app UI | Packet reaches C, uploads, C originates an AckPacket, ack returns to A, A shows "Delivered" | `payload_received`/relay logs on B; upload success log on C | Elapsed time A→"Delivered"; screenshot of A's history screen |
| 2 | Invalid signature packet | A, B — needs a way to inject a hand-crafted packet with a tampered `signature` field (a debug/test hook, since the real app UI always signs correctly — document exactly how this was done on the day, e.g. a debug build flag or a raw Nearby Connections payload sent from a test harness) | Send B a packet identical to a valid one except the `signature` field is corrupted | B logs `signature verification failed packet_id=... reason=INVALID_SIGNATURE` (new Sprint 5 log line — see `MeshForegroundService.onPayloadReceived`), `signatureFailures` in `getRelayStats` increments, packet is NOT relayed, NOT added to B's dedup cache | The new `Log.w` line specifically; `getRelayStats` before/after | logcat excerpt showing the warning line; two `getRelayStats` snapshots showing the counter delta |
| 3 | Multi-hop relay | A↔B↔C↔D chain (3 hops) | A originates | Packet reaches D (or wherever the exit node is) via B and C, hop_count increments correctly at each hop | Relay logs on B and C showing hop_count progression | hop_count value observed at each intermediate device, if loggable/inspectable |
| 4 | Duplicate packet | A, B | A's packet reaches B twice (natural retransmission, or a deliberate resend of the same bytes) | B's `duplicatesFiltered` increments; packet relayed only once | `getRelayStats` before/after | Counter delta |
| 5 | TTL exhaustion | A, B, C, D in a chain longer than `MAX_TTL` hops, OR a hand-crafted packet with `ttl=1` | Originate/send a packet whose TTL will hit 0 partway through the chain | Propagation stops at the device where TTL reaches 0; no further relay | Relay logs at the stopping device | Confirm no downstream device ever received it |
| 6 | ACK delivery | Scenario 1's continuation | After C uploads and acks, confirm the ack's `AckPacket` relays back through B to A correctly | A's history/status screen reflects the ack | Ack relay logs on B | Screenshot / status transition on A |
| 7 | Termination | A responder-side termination flow (if the app UI/backend exposes triggering this — otherwise document as not exercisable without a responder account) | Trigger a `TerminationPacket` for an active emergency | Relayed and applied per `ACK_LIFECYCLE.md`'s documented termination behavior; responder-registry authorization check (Dart-side) still applies unchanged | Relevant relay + Dart-side logs | Status transition confirming termination took effect |
| 8 | Offline store-forward | A, B — B has no internet | A originates; B receives but cannot immediately exit to backend | Packet queues on B (`LocalQueueService`), not lost | Queue-related logs on B | Confirm packet still present in B's local queue |
| 9 | Internet restoration | Continuation of #8 | Bring B (or whichever device holds the queued packet) online | Queued packet uploads via the existing retry timer; A eventually shows "Delivered" | Upload-retry logs | Elapsed time from restoration to successful upload |
| 10 | Battery power saver | Any one device, genuinely low battery or `updateMeshPolicy` forced into power-saver tier | Confirm duty-cycle behavior (advertise/discover only during bursts) | Device still discoverable, on a longer interval; relay still eventually happens | Duty-cycle start/stop logs | Observed cycle timing vs. the configured interval |
| 11 | Bluetooth OFF → ON | Any one device | Toggle Bluetooth off, wait, toggle back on | Mesh resumes automatically (Sprint 3's `registerRadioStateReceiver`) without an app restart | `"Bluetooth turned back on -- resuming duty cycle"` log line | logcat excerpt |
| 12 | Wi-Fi OFF → ON | Any one device | Same as #11 for Wi-Fi | Same pass criteria | `"Wi-Fi turned back on -- resuming duty cycle"` log line | logcat excerpt |
| 13 | Forced service restart | Any one device with active dedup state | Force-stop the app process; let `START_STICKY` restart the service | `"Restored persisted mesh policy..."` log line appears; service resumes | That log line | logcat excerpt |
| 14 | START_STICKY dedup restoration | Continuation of #13 | Re-send a packet the device had already seen BEFORE the forced restart | Device does NOT re-relay it (persisted `seen` cache survived) — `duplicatesFiltered` increments, not a fresh relay | `getRelayStats` before/after | Counter delta; confirm no duplicate relay observed downstream |
| 15 | Invalid packet must never relay (end-to-end, multi-device) | A (hand-crafted invalid packet), B, C | Send an invalid-signature packet toward B; confirm it does NOT propagate to C even indirectly | C never receives it, in any form, at any point | Logs on B (rejection) AND C (absence of receipt — a negative observation, so timebox the wait and note how long was waited) | logcat from B showing rejection; explicit confirmation C's logs show nothing for that packet_id over the wait window |

## What this runbook does NOT cover

Same exclusions as `MULTI_DEVICE_TEST_PLAN.md`: scale beyond 4 devices,
and any true adversarial fuzzing beyond the fixed scenarios above (a
broader security-test exercise, tracked separately). Connection
authentication is unchanged (still auto-accept) — no device test can
validate an authentication mechanism that doesn't exist yet.

## Before running this

1. A real APK build is required first — none has been produced anywhere
   in this engagement (see `docs/mesh/SPRINT5_INTEGRATION_VALIDATION.md`
   §9 for the exact, current build blocker).
2. Decide and document, in advance, exactly how scenario 2 and 15's
   "hand-crafted invalid packet" will be produced on real devices — this
   runbook deliberately does not prescribe one specific mechanism (a debug
   build flag, a small standalone test harness app, or a raw Nearby
   Connections payload injector), since that choice depends on what the
   real build actually exposes, which this sandbox cannot determine.
