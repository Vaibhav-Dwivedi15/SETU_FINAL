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
* **Acknowledgement:** `MeshLocator`'s existing ack listener calls
  `RecoveryRepository.updateStatusByEmergencyId(id, 'Delivered')`; only a
  `pendingSync` report with that `emergencyId` becomes `submitted`. An ack is
  originated by any node that receives the packet, so it proves network
  receipt only.
* **Backend:** there is no dedicated recovery endpoint. Reports reach the
  backend, if at all, as ordinary low-priority ingests carrying a
  `[RECOVERY:*]` message prefix that nothing parses today. A real
  damage/missing-person/resource API would replace `RecoveryDispatcher`
  (`recovery_dispatcher.dart`) only.
* **Priority:** never `critical` (reserved for live SOS); missing person is
  `high`, others follow severity/urgency.
* **Privacy:** a dispatched missing-person report puts the name, age and
  description into a mesh packet that is signed but not encrypted.

## Deferred
Optional photo attachment: the app has no image-picker dependency, and none
was added.
