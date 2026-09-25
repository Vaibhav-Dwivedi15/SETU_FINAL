/// Where an entry in the Emergency Contacts list came from. Every entry
/// is something the user saved themselves: SETU bundles no official
/// government numbers, so none are listed here.
enum EmergencyContactSource {
  plan('Emergency plan'),
  saved('Saved contact');

  const EmergencyContactSource(this.label);
  final String label;
}

class EmergencyContact {
  const EmergencyContact({
    required this.name,
    required this.purpose,
    required this.phone,
    required this.source,
  });

  final String name;
  final String purpose;
  final String phone;
  final EmergencyContactSource source;

  /// Dialer URI, or null if the number has no dialable characters.
  Uri? get dialUri {
    final digits = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    return digits.isEmpty ? null : Uri(scheme: 'tel', path: digits);
  }
}
