# Prepare and Recovery modules (mobile)

Navigation: `HOME | PREPARE | RECOVERY | HISTORY` (existing bottom bar). Route tables:
`setu_app/lib/routes/prepare_recovery_routes.dart`.

## Prepare (fully offline)
Guides, checklists and the emergency kit are bundled JSON (`assets/preparedness/`,
`assets/recovery/`); nothing is fetched. Adding a disaster is a JSON entry
(`sections`: before / during / after / avoid). Checklist ticks, the emergency
plan and the contact list are stored in SharedPreferences on the device.
SETU bundles **no official government numbers**; Emergency Contacts shows only
what the user saved (plan contacts and SOS contacts) and opens the dialer via
`tel:`. It reports only whether the OS accepted the request.

## Recovery: report lifecycle
`RecoveryRepository` owns `draft -> pendingSync -> submitted | failed`.
Every state is written to `RecoveryReportStore` before anything is attempted,
so a report is never lost to a crash, a denied permission or no connectivity.

| Status | Meaning |
| --- | --- |
| Draft | Being written; never sent. |
| Pending sync | Saved locally and handed to the mesh store-and-forward queue. |
| Submitted | A SETU node acknowledged receipt. **Not** confirmation that an authority reviewed it. |
| Failed | The hand-off failed; the report stays saved and can be retried. |

## Integration boundary
* **Transport:** the existing signed `EmergencyPacket` path
  (`RecoveryPacketBuilder` + `MeshServiceImpl.originate`). No new packet type,
  no change to `signaturePayload`, no mesh or native changes.
* **What an acknowledgement is:** the mesh originates an ACK only after a
  node's upload of the packet was accepted (or already held) by the backend
  `/ingest` (`MeshServiceImpl._markPacketDelivered`), and it reaches the
  originating device over the mesh. `RecoveryRepository.updateStatusByEmergencyId`
  turns it into **Submitted**, and only for a report that is Pending sync and
  carries the matching `emergencyId`. It is a receipt: it never means an
  authority has seen, acted on or resolved the report.
* **Backend:** there is no dedicated recovery endpoint. Reports reach the
  backend, if at all, as ordinary low-priority ingests carrying a
  `[RECOVERY:*]` message prefix that nothing parses today. A real
  damage/missing-person/resource API would replace `RecoveryDispatcher`
  (`recovery_dispatcher.dart`) only.
* **Priority:** never `critical` (reserved for live SOS); missing person is
  `high`, others follow severity/urgency.

## Correctness guarantees (and the tests that pin them)
* **Writes never clobber each other.** Store writes are serialized
  process-wide, and every change to one report runs one at a time and checks
  the *stored* status, not the caller's copy. So a stale form cannot reset a
  queued report to draft, a double tap cannot send two packets, and an ACK
  cannot be lost to a concurrent save (`recovery_hardening_test.dart`).
* **`emergencyId` is stored before the packet is handed to the transport**,
  so an ACK can always be matched.
* **A radio hand-off failure after the packet was durably queued is not
  reported as Failed.** `MeshServiceImpl.originate` writes to the durable
  upload queue before calling the native layer, which can still fail (for
  example `SERVICE_UNAVAILABLE`). The queued packet will be uploaded, so a
  Retry would send the report twice; the dispatcher checks the durable queue
  and reports Pending sync instead.
* **Unreadable stored entries are kept**, not deleted on the next write.
* **Signing:** `recovery_packet_signing_test.dart` verifies real Ed25519
  signatures over recovery packets: every signed field is tamper-evident,
  `ttl`/`hopCount` are outside the signature, and each dispatch is a fresh
  packet (new id, nonce, timestamp).

## Privacy
Nothing here is encrypted. Packets are signed, not encrypted, so a dispatched
missing-person report puts the name, age and description on the mesh in
readable form. On the device, reports are plain SharedPreferences (not in
Android backups, which exclude `sharedpref`), protected only by the app
sandbox.

## Known limitations (transport-level; not changed here)
* **Old reports are rejected by the backend.** `/ingest` refuses packets whose
  signed timestamp is older than 1 hour (`PACKET_MAX_AGE_SECONDS`), and a
  packet's timestamp is fixed when the report is submitted. A report saved
  while offline for more than an hour will be rejected on upload, and the app
  currently keeps showing Pending sync (the rejection is visible only in the
  relay log). Fixing this needs a product decision (for example re-signing
  stale pending reports) and a mesh-layer signal.
* **Backend acceptance is not observable on its own device.** Acks travel
  over the mesh, so an online device with no peers never receives its own
  ack: its report stays Pending sync even though the backend accepted it.
  The same applies to SOS history.
* **Acks after an app restart are ignored** because the mesh keeps the set of
  originated emergency ids in memory only.
* A Pending sync report has no timeout; only a Failed report offers Retry.

## Deferred
Optional photo attachment: the app has no image-picker dependency, and none
was added.
