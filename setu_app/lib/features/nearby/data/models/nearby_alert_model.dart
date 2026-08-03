import '../../../sos/data/models/alert_mode.dart';

class NearbyAlertModel {
  final String id;
  final AlertMode alertMode;
  final double latitude;
  final double longitude;
  final DateTime timestamp;
  final double radius;
  final String status;

  NearbyAlertModel({
    required this.id,
    required this.alertMode,
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    required this.radius,
    required this.status,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'alertMode': alertMode.name,
      'latitude': latitude,
      'longitude': longitude,
      'timestamp': timestamp.toIso8601String(),
      'radius': radius,
      'status': status,
    };
  }

  factory NearbyAlertModel.fromJson(Map<String, dynamic> json) {
    return NearbyAlertModel(
      id: json['id'],
      alertMode: (json['alertMode'] ?? "private") == "public"
          ? AlertMode.public
          : AlertMode.private,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      timestamp: DateTime.parse(json['timestamp']),
      radius: (json['radius'] as num).toDouble(),
      status: json['status'],
    );
  }
}
