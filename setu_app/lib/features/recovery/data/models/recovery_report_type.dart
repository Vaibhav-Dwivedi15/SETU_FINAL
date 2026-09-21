import 'package:flutter/material.dart';

import 'package:setu_app/mesh/enums/emergency_priority.dart';

// =====================================================
// SETU Project
// Module : Recovery (AFTER-disaster) / report type
// Priority 8 (session brief) -- damage reporting, missing-person
// reporting, resource availability, recovery status, community updates.
// =====================================================
//
// DELIBERATELY NOT A NEW PacketType / wire-format field. Every recovery
// report travels as a normal, already-signed EmergencyPacket (see
// RecoveryPacketBuilder) -- reusing the exact same relay engine, TTL,
// dedup, store-and-forward queue and backend ingestion as a live SOS.
// This enum only decides two purely client-side things: which prefix
// goes in front of EmergencyPacket.message (so the backend's existing
// keyword-based incident_type fallback and any human reading the
// dashboard can tell a recovery report from an active emergency at a
// glance) and which EmergencyPriority to sign it with. Nothing here
// touches signaturePayload, mesh_service.dart, or any native code.
enum RecoveryReportType {
  damage,
  missingPerson,
  resourceAvailable,
  recoveryStatus,
  communityUpdate,
}

extension RecoveryReportTypeExtension on RecoveryReportType {
  String get title {
    switch (this) {
      case RecoveryReportType.damage:
        return 'Damage report';
      case RecoveryReportType.missingPerson:
        return 'Missing person';
      case RecoveryReportType.resourceAvailable:
        return 'Resource available';
      case RecoveryReportType.recoveryStatus:
        return 'Recovery status';
      case RecoveryReportType.communityUpdate:
        return 'Community update';
    }
  }

  String get subtitle {
    switch (this) {
      case RecoveryReportType.damage:
        return 'Report damaged buildings, roads, or infrastructure';
      case RecoveryReportType.missingPerson:
        return 'Report someone missing or share information found';
      case RecoveryReportType.resourceAvailable:
        return 'Share food, water, shelter, or medical supplies you can offer';
      case RecoveryReportType.recoveryStatus:
        return "Mark yourself or your area's status (safe, needs help, etc.)";
      case RecoveryReportType.communityUpdate:
        return 'Share a general update with your community';
    }
  }

  IconData get icon {
    switch (this) {
      case RecoveryReportType.damage:
        return Icons.domain_disabled;
      case RecoveryReportType.missingPerson:
        return Icons.person_search;
      case RecoveryReportType.resourceAvailable:
        return Icons.volunteer_activism;
      case RecoveryReportType.recoveryStatus:
        return Icons.health_and_safety;
      case RecoveryReportType.communityUpdate:
        return Icons.campaign;
    }
  }

  /// Prepended to the report text before it goes into
  /// EmergencyPacket.message. Machine-parseable ("[RECOVERY:DAMAGE] ")
  /// so a future dashboard/backend pass can filter on it without a
  /// schema change, and human-readable as-is in the meantime.
  String get messagePrefix {
    switch (this) {
      case RecoveryReportType.damage:
        return '[RECOVERY:DAMAGE]';
      case RecoveryReportType.missingPerson:
        return '[RECOVERY:MISSING_PERSON]';
      case RecoveryReportType.resourceAvailable:
        return '[RECOVERY:RESOURCE]';
      case RecoveryReportType.recoveryStatus:
        return '[RECOVERY:STATUS]';
      case RecoveryReportType.communityUpdate:
        return '[RECOVERY:UPDATE]';
    }
  }

  /// Recovery-phase reports are, almost by definition, lower urgency
  /// than a live SOS (the disaster's acute phase has passed) -- EXCEPT
  /// a missing-person report, which stays HIGH since it can still be
  /// time-critical. Never CRITICAL: that tier is reserved for active,
  /// originating emergencies (fire/collapse/earthquake, see
  /// EmergencyPacketBuilder._priorityForCategory) so a flood of
  /// recovery-phase traffic can never compete with or bury a live SOS
  /// in PriorityRelayQueue's tiering.
  EmergencyPriority get priority {
    switch (this) {
      case RecoveryReportType.missingPerson:
        return EmergencyPriority.high;
      case RecoveryReportType.recoveryStatus:
        return EmergencyPriority.medium;
      case RecoveryReportType.damage:
      case RecoveryReportType.resourceAvailable:
      case RecoveryReportType.communityUpdate:
        return EmergencyPriority.low;
    }
  }
}
