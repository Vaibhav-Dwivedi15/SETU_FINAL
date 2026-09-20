import 'package:flutter/material.dart';

import 'package:setu_app/core/constants/app_colors.dart';

import '../../data/models/nearby_alert_model.dart';
import '../../data/repositories/nearby_repository.dart';

class NearbyScreen extends StatefulWidget {
  const NearbyScreen({super.key});

  @override
  State<NearbyScreen> createState() => _NearbyScreenState();
}

class _NearbyScreenState extends State<NearbyScreen> {
  final NearbyRepository repository = NearbyRepository();

  List<NearbyAlertModel> alerts = [];

  @override
  void initState() {
    super.initState();
    loadAlerts();
  }

  Future<void> loadAlerts() async {
    // Aug 5 2026: this list now genuinely includes real incoming
    // AlertPackets from other nearby SETU devices, not just this
    // device's own local public-SOS copy -- see MeshLocator's alert
    // listener, which writes real incoming alerts into the same
    // NearbyRepository this screen already reads from. Pull-to-refresh
    // (below) is how a newly-arrived alert becomes visible if one
    // comes in while this screen is already open -- same honestly-
    // scoped choice as history_screen.dart's refresh pattern.
    alerts = await repository.getAlerts();

    if (!mounted) return;

    setState(() {});
  }

  Widget _buildEmptyState() {
    return ListView(
      children: const [
        SizedBox(height: 120),
        Icon(Icons.people_alt_outlined, size: 90, color: Colors.grey),
        SizedBox(height: 20),
        Center(
          child: Text(
            "No Nearby Alerts",
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
        ),
        SizedBox(height: 12),
        Center(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              "Public SOS alerts broadcast nearby will appear here.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Nearby Alerts")),
      body: RefreshIndicator(
        onRefresh: loadAlerts,
        child: alerts.isEmpty
            ? _buildEmptyState()
            : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: alerts.length,
                itemBuilder: (context, index) {
                  final alert = alerts[index];
                  final hasIncidentType = alert.incidentType.isNotEmpty;

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(12),
                      leading: Container(
                        height: 46,
                        width: 46,
                        decoration: const BoxDecoration(
                          gradient: AppColors.primaryGradient,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.warning_amber_rounded,
                          color: Colors.white,
                        ),
                      ),
                      title: Text(
                        hasIncidentType
                            ? alert.incidentType.toUpperCase()
                            : alert.alertMode.name.toUpperCase(),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        "Lat: ${alert.latitude}\nLng: ${alert.longitude}",
                      ),
                      isThreeLine: true,
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
