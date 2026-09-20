// =====================================================
// SETU Project
// Module : Lost Child Alert (UI-only)
// Owner  : Sudheer
// =====================================================
//
// PHASE 1 SCOPE NOTE:
// Local/display model only. There is no "lost child" packet
// type in the mesh layer — that would be a new packet type
// beyond emergency/termination (Phase 2, needs team-lead
// sign-off per the extension doc, Section 3). The "Broadcast"
// button on the compose screen is a UI stub for this reason.

class LostChildAlertModel {
  final String childName;
  final int age;
  final String description; // clothing, appearance, distinguishing marks
  final String lastSeenLocation;
  final DateTime lastSeenTime;
  final String guardianContact;

  const LostChildAlertModel({
    required this.childName,
    required this.age,
    required this.description,
    required this.lastSeenLocation,
    required this.lastSeenTime,
    required this.guardianContact,
  });
}
