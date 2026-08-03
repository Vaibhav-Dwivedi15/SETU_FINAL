// =====================================================
// SETU Project
// Module : Community / Volunteer Notification (UI-only)
// Owner  : Sudheer
// =====================================================
//
// PHASE 1 SCOPE NOTE:
// This model is local/display-only. It does NOT extend or
// relate to EmergencyPacket/MeshPacket/TerminationPacket in
// any way, and nothing here is sent through the mesh layer.
// Real volunteer-matching, radius logic, and response
// tracking are backend + team-lead-approved packet-schema
// work (Phase 2) — not implemented here.

class VolunteerAlertModel {
  final String incidentType;
  final double distanceKm;
  final DateTime timestamp;
  final String priority; // "low" | "medium" | "high" | "critical"
  final String emergencyContact;
  final double latitude;
  final double longitude;

  const VolunteerAlertModel({
    required this.incidentType,
    required this.distanceKm,
    required this.timestamp,
    required this.priority,
    required this.emergencyContact,
    required this.latitude,
    required this.longitude,
  });
}
