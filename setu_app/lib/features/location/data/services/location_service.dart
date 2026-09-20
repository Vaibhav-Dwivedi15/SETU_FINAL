import 'package:geolocator/geolocator.dart';

import '../models/location_model.dart';

class LocationService {
  Future<LocationModel> getCurrentLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      throw Exception("Location service is disabled.");
    }

    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      throw Exception("Location permission denied.");
    }

    if (permission == LocationPermission.deniedForever) {
      throw Exception("Location permission permanently denied.");
    }

    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
    );

    final Position position = await Geolocator.getCurrentPosition(
      locationSettings: locationSettings,
    );

    return LocationModel(
      latitude: position.latitude,
      longitude: position.longitude,
    );
  }
}
