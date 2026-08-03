class SettingsModel {
  final int sosCountdown;

  final bool autoRetry;

  final bool highAccuracyLocation;

  final bool stealthMode;

  final bool relayEnabled;

  /// 'tap' — single tap, then the existing countdown dialog
  /// (SOS Countdown setting above) gives the wait-and-cancel window.
  /// 'hold' — 3-second physical hold gesture on the home button.
  final String sosTriggerMode;

  /// Set once Login (name + OTP-verified phone) completes.
  /// Empty means login hasn't been completed — app_router.dart
  /// redirects to /login until this is filled in.
  final String userName;

  final String phoneNumber;

  /// Optional — filled in via "Complete Your Profile", not at
  /// login.
  final String bloodGroup;

  /// Optional medical note (allergies, conditions) — shown to
  /// responders if the phone is found. Filled in via "Complete
  /// Your Profile".
  final String medicalNote;

  /// Language selection. UI-only for now — the selection is
  /// saved and shown correctly, but app-wide translation isn't
  /// wired yet (needs the intl package + generated ARB files,
  /// a separate larger piece of work).
  final String languageCode;

  const SettingsModel({
    required this.sosCountdown,
    required this.autoRetry,
    required this.highAccuracyLocation,
    required this.stealthMode,
    required this.relayEnabled,
    required this.sosTriggerMode,
    required this.userName,
    required this.phoneNumber,
    required this.bloodGroup,
    required this.medicalNote,
    required this.languageCode,
  });

  factory SettingsModel.defaultSettings() {
    return const SettingsModel(
      sosCountdown: 5,
      autoRetry: true,
      highAccuracyLocation: true,
      stealthMode: false,
      relayEnabled: false,
      sosTriggerMode: 'tap',
      userName: '',
      phoneNumber: '',
      bloodGroup: '',
      medicalNote: '',
      languageCode: 'en',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'sosCountdown': sosCountdown,
      'autoRetry': autoRetry,
      'highAccuracyLocation': highAccuracyLocation,
      'stealthMode': stealthMode,
      'relayEnabled': relayEnabled,
      'sosTriggerMode': sosTriggerMode,
      'userName': userName,
      'phoneNumber': phoneNumber,
      'bloodGroup': bloodGroup,
      'medicalNote': medicalNote,
      'languageCode': languageCode,
    };
  }

  factory SettingsModel.fromJson(Map<String, dynamic> json) {
    return SettingsModel(
      sosCountdown: json['sosCountdown'] ?? 5,
      autoRetry: json['autoRetry'] ?? true,
      highAccuracyLocation: json['highAccuracyLocation'] ?? true,
      stealthMode: json['stealthMode'] ?? false,
      relayEnabled: json['relayEnabled'] ?? false,
      sosTriggerMode: json['sosTriggerMode'] ?? 'tap',
      userName: json['userName'] ?? '',
      phoneNumber: json['phoneNumber'] ?? '',
      bloodGroup: json['bloodGroup'] ?? '',
      medicalNote: json['medicalNote'] ?? '',
      languageCode: json['languageCode'] ?? 'en',
    );
  }

  SettingsModel copyWith({
    int? sosCountdown,
    bool? autoRetry,
    bool? highAccuracyLocation,
    bool? stealthMode,
    bool? relayEnabled,
    String? sosTriggerMode,
    String? userName,
    String? phoneNumber,
    String? bloodGroup,
    String? medicalNote,
    String? languageCode,
  }) {
    return SettingsModel(
      sosCountdown: sosCountdown ?? this.sosCountdown,
      autoRetry: autoRetry ?? this.autoRetry,
      highAccuracyLocation: highAccuracyLocation ?? this.highAccuracyLocation,
      stealthMode: stealthMode ?? this.stealthMode,
      relayEnabled: relayEnabled ?? this.relayEnabled,
      sosTriggerMode: sosTriggerMode ?? this.sosTriggerMode,
      userName: userName ?? this.userName,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      bloodGroup: bloodGroup ?? this.bloodGroup,
      medicalNote: medicalNote ?? this.medicalNote,
      languageCode: languageCode ?? this.languageCode,
    );
  }
}
