// =====================================================
// SETU Project
// Module : Child Safety Mode (UI + local storage only)
// Owner  : Sudheer
// =====================================================
//
// PHASE 1 SCOPE NOTE:
// This model is stored locally only (SharedPreferences, same
// pattern as ContactModel/HistoryModel). It is NOT sent to
// any backend and does NOT extend EmergencyPacket or any
// mesh packet type. A "Lost Child" broadcast packet type
// would be new packet-schema territory (Phase 2) — needs
// team-lead sign-off before any packet field is added for
// this data.

class ChildProfileModel {
  final String id;
  final String childName;
  final int childAge;
  final String childIdNumber; // school ID / any local identifier, not Aadhaar
  final String guardianName;
  final String guardianRelation;
  final String guardianPhone;
  final String medicalInfo; // allergies, conditions, blood group, etc.
  final String homeAddress;
  final String schoolAddress;

  const ChildProfileModel({
    required this.id,
    required this.childName,
    required this.childAge,
    required this.childIdNumber,
    required this.guardianName,
    required this.guardianRelation,
    required this.guardianPhone,
    required this.medicalInfo,
    required this.homeAddress,
    required this.schoolAddress,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'childName': childName,
      'childAge': childAge,
      'childIdNumber': childIdNumber,
      'guardianName': guardianName,
      'guardianRelation': guardianRelation,
      'guardianPhone': guardianPhone,
      'medicalInfo': medicalInfo,
      'homeAddress': homeAddress,
      'schoolAddress': schoolAddress,
    };
  }

  factory ChildProfileModel.fromJson(Map<String, dynamic> json) {
    return ChildProfileModel(
      id: json['id'],
      childName: json['childName'],
      childAge: json['childAge'] ?? 0,
      childIdNumber: json['childIdNumber'] ?? '',
      guardianName: json['guardianName'] ?? '',
      guardianRelation: json['guardianRelation'] ?? '',
      guardianPhone: json['guardianPhone'] ?? '',
      medicalInfo: json['medicalInfo'] ?? '',
      homeAddress: json['homeAddress'] ?? '',
      schoolAddress: json['schoolAddress'] ?? '',
    );
  }
}
