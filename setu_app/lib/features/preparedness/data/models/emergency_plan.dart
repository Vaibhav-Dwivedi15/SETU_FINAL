/// A family's local emergency plan. Deliberately minimal: two contacts, a
/// meeting point and free-text notes -- no identity documents, addresses
/// or medical data.
class EmergencyPlan {
  const EmergencyPlan({
    this.primaryName = '',
    this.primaryPhone = '',
    this.secondaryName = '',
    this.secondaryPhone = '',
    this.meetingPoint = '',
    this.notes = '',
  });

  static const EmergencyPlan empty = EmergencyPlan();

  final String primaryName;
  final String primaryPhone;
  final String secondaryName;
  final String secondaryPhone;
  final String meetingPoint;
  final String notes;

  bool get isEmpty =>
      primaryName.isEmpty &&
      primaryPhone.isEmpty &&
      secondaryName.isEmpty &&
      secondaryPhone.isEmpty &&
      meetingPoint.isEmpty &&
      notes.isEmpty;

  /// Field -> error. A phone number is optional, but if given it must
  /// have 7-15 digits (formatting characters are ignored).
  Map<String, String> validate() {
    final errors = <String, String>{};
    if (!_phoneOk(primaryPhone)) errors['primaryPhone'] = 'Enter a valid phone number (7-15 digits).';
    if (!_phoneOk(secondaryPhone)) errors['secondaryPhone'] = 'Enter a valid phone number (7-15 digits).';
    return errors;
  }

  static bool _phoneOk(String phone) {
    if (phone.trim().isEmpty) return true;
    if (RegExp(r'[^0-9+\-\s()]').hasMatch(phone)) return false;
    final digits = phone.replaceAll(RegExp(r'\D'), '').length;
    return digits >= 7 && digits <= 15;
  }

  EmergencyPlan copyWith({
    String? primaryName,
    String? primaryPhone,
    String? secondaryName,
    String? secondaryPhone,
    String? meetingPoint,
    String? notes,
  }) =>
      EmergencyPlan(
        primaryName: primaryName ?? this.primaryName,
        primaryPhone: primaryPhone ?? this.primaryPhone,
        secondaryName: secondaryName ?? this.secondaryName,
        secondaryPhone: secondaryPhone ?? this.secondaryPhone,
        meetingPoint: meetingPoint ?? this.meetingPoint,
        notes: notes ?? this.notes,
      );

  Map<String, dynamic> toJson() => {
        'primaryName': primaryName,
        'primaryPhone': primaryPhone,
        'secondaryName': secondaryName,
        'secondaryPhone': secondaryPhone,
        'meetingPoint': meetingPoint,
        'notes': notes,
      };

  factory EmergencyPlan.fromJson(Map<String, dynamic> json) => EmergencyPlan(
        primaryName: json['primaryName'] as String? ?? '',
        primaryPhone: json['primaryPhone'] as String? ?? '',
        secondaryName: json['secondaryName'] as String? ?? '',
        secondaryPhone: json['secondaryPhone'] as String? ?? '',
        meetingPoint: json['meetingPoint'] as String? ?? '',
        notes: json['notes'] as String? ?? '',
      );
}
