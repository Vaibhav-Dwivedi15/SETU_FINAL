class LocationModel {
  final double latitude;
  final double longitude;

  const LocationModel({required this.latitude, required this.longitude});

  String get googleMapsUrl {
    return "https://www.google.com/maps/search/?api=1&query=$latitude,$longitude";
  }

  @override
  String toString() {
    return "Latitude: $latitude, Longitude: $longitude";
  }
}
