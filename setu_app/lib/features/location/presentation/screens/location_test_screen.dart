import 'package:flutter/material.dart';

import '../../data/models/location_model.dart';
import '../../data/services/location_service.dart';

class LocationTestScreen extends StatefulWidget {
  const LocationTestScreen({super.key});

  @override
  State<LocationTestScreen> createState() => _LocationTestScreenState();
}

class _LocationTestScreenState extends State<LocationTestScreen> {
  final LocationService _locationService = LocationService();

  bool isLoading = false;

  LocationModel? location;

  String? error;

  Future<void> getLocation() async {
    setState(() {
      isLoading = true;
      error = null;
    });

    try {
      final result = await _locationService.getCurrentLocation();

      setState(() {
        location = result;
      });
    } catch (e) {
      setState(() {
        error = e.toString().replaceFirst("Exception: ", "");
      });
    }

    setState(() {
      isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("GPS Location Test")),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const SizedBox(height: 30),

            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                onPressed: isLoading ? null : getLocation,
                child: Text(
                  isLoading ? "Getting Location..." : "Get Current Location",
                ),
              ),
            ),

            const SizedBox(height: 30),

            if (location != null) ...[
              SelectableText(
                "Latitude : ${location!.latitude}",
                style: const TextStyle(fontSize: 18),
              ),

              const SizedBox(height: 10),

              SelectableText(
                "Longitude : ${location!.longitude}",
                style: const TextStyle(fontSize: 18),
              ),

              const SizedBox(height: 20),

              SelectableText(
                location!.googleMapsUrl,
                style: const TextStyle(color: Colors.blue),
              ),
            ],

            if (error != null) ...[
              Text(
                error!,
                style: const TextStyle(color: Colors.red, fontSize: 16),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
