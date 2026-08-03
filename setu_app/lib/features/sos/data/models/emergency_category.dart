// =====================================================
// SETU Project
// Module : SOS / Emergency Category
// Owner  : Sudheer
// =====================================================
//
// Block 14 update: category selection is now actionable — it
// changes the actual SMS message text via SosRepository (see
// alertHeading below). It is STILL not wired into
// EmergencyPacket.priority or any mesh packet field — that
// remains Phase 2 (needs team-lead sign-off), since it would
// change the frozen packet schema. This only affects the
// plain-text SMS body, which is entirely within this module's
// own scope.

import 'package:flutter/material.dart';

enum EmergencyCategory {
  generalSos,
  roadAccident,
  seniorCitizenAssistance,
  violence,
  suspiciousActivity,
  medical,
  fire,
}

extension EmergencyCategoryExtension on EmergencyCategory {
  String get title {
    switch (this) {
      case EmergencyCategory.generalSos:
        return 'General SOS';
      case EmergencyCategory.roadAccident:
        return 'Road Accident';
      case EmergencyCategory.seniorCitizenAssistance:
        return 'Senior Citizen Assistance';
      case EmergencyCategory.violence:
        return 'Violence';
      case EmergencyCategory.suspiciousActivity:
        return 'Suspicious Activity';
      case EmergencyCategory.medical:
        return 'Medical Emergency';
      case EmergencyCategory.fire:
        return 'Fire';
    }
  }

  IconData get icon {
    switch (this) {
      case EmergencyCategory.generalSos:
        return Icons.warning_amber_rounded;
      case EmergencyCategory.roadAccident:
        return Icons.car_crash;
      case EmergencyCategory.seniorCitizenAssistance:
        return Icons.elderly;
      case EmergencyCategory.violence:
        return Icons.report;
      case EmergencyCategory.suspiciousActivity:
        return Icons.visibility;
      case EmergencyCategory.medical:
        return Icons.medical_services;
      case EmergencyCategory.fire:
        return Icons.local_fire_department;
    }
  }

  /// Category-specific line used in the actual SMS message
  /// text (see SosRepository.triggerSOS).
  String get alertHeading {
    switch (this) {
      case EmergencyCategory.generalSos:
        return 'I need immediate help.';
      case EmergencyCategory.roadAccident:
        return "I've been in a road accident and need immediate help.";
      case EmergencyCategory.seniorCitizenAssistance:
        return 'A senior citizen nearby needs immediate assistance.';
      case EmergencyCategory.violence:
        return "I'm in danger and need immediate help right now.";
      case EmergencyCategory.suspiciousActivity:
        return "I've spotted suspicious activity and need someone to check on this.";
      case EmergencyCategory.medical:
        return 'This is a medical emergency — I need immediate help.';
      case EmergencyCategory.fire:
        return "There's a fire emergency — I need immediate help.";
    }
  }
}
