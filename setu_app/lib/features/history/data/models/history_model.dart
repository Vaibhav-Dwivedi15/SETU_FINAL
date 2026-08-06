import '../../../sos/data/models/alert_mode.dart';

class HistoryModel {
  final String id;

  final DateTime timestamp;

  final double latitude;
  final double longitude;

  final List<String> recipients;

  final String status;

  final String message;

  final String mapsLink;

  final AlertMode alertMode;

  // Delivery Info
  final int retryCount;

  final String errorReason;

  final bool locationAttached;

  // Aug 5 2026: added so a later real ack (MeshService.acknowledgments)
  // can find and update THIS specific history entry's status --
  // previously there was no way to correlate an incoming ack back to
  // the history row it belongs to. Nullable/defaults to '' for
  // backward compatibility with history entries written before this
  // field existed (fromJson below falls back to '' if absent).
  final String emergencyId;

  HistoryModel({
    required this.id,
    required this.timestamp,
    required this.latitude,
    required this.longitude,
    required this.recipients,
    required this.status,
    required this.message,
    required this.mapsLink,
    required this.alertMode,
    required this.retryCount,
    required this.errorReason,
    required this.locationAttached,
    this.emergencyId = '',
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'timestamp': timestamp.toIso8601String(),
      'latitude': latitude,
      'longitude': longitude,
      'recipients': recipients,
      'status': status,
      'message': message,
      'mapsLink': mapsLink,
      'alertMode': alertMode.name,
      'retryCount': retryCount,
      'errorReason': errorReason,
      'locationAttached': locationAttached,
      'emergencyId': emergencyId,
    };
  }

  factory HistoryModel.fromJson(Map<String, dynamic> json) {
    return HistoryModel(
      id: json['id'],
      timestamp: DateTime.parse(json['timestamp']),
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      recipients: List<String>.from(json['recipients']),
      status: json['status'],
      message: json['message'],
      mapsLink: json['mapsLink'],

      alertMode: (json['alertMode'] ?? "private") == "public"
          ? AlertMode.public
          : AlertMode.private,

      retryCount: json['retryCount'] ?? 0,
      errorReason: json['errorReason'] ?? "",
      locationAttached: json['locationAttached'] ?? true,
      emergencyId: json['emergencyId'] ?? '',
    );
  }

  HistoryModel copyWith({
    String? id,
    DateTime? timestamp,
    double? latitude,
    double? longitude,
    List<String>? recipients,
    String? status,
    String? message,
    String? mapsLink,
    AlertMode? alertMode,
    int? retryCount,
    String? errorReason,
    bool? locationAttached,
    String? emergencyId,
  }) {
    return HistoryModel(
      id: id ?? this.id,
      timestamp: timestamp ?? this.timestamp,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      recipients: recipients ?? this.recipients,
      status: status ?? this.status,
      message: message ?? this.message,
      mapsLink: mapsLink ?? this.mapsLink,
      alertMode: alertMode ?? this.alertMode,
      retryCount: retryCount ?? this.retryCount,
      errorReason: errorReason ?? this.errorReason,
      locationAttached: locationAttached ?? this.locationAttached,
      emergencyId: emergencyId ?? this.emergencyId,
    );
  }
}
