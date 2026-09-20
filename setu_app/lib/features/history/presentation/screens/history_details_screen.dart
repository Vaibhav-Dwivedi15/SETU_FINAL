import 'package:flutter/material.dart';

import '../../data/models/history_model.dart';

class HistoryDetailsScreen extends StatelessWidget {
  final HistoryModel history;

  const HistoryDetailsScreen({super.key, required this.history});

  Widget _buildTile(IconData icon, String title, String value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.red, size: 28),

          const SizedBox(width: 16),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),

                const SizedBox(height: 5),

                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xffF6F8FC),

      appBar: AppBar(
        elevation: 0,
        centerTitle: true,
        backgroundColor: Colors.red,
        foregroundColor: Colors.white,
        title: const Text("Incident Details"),
      ),

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(18),

        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),

              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
              ),

              child: Column(
                children: [
                  CircleAvatar(
                    radius: 38,
                    backgroundColor: Colors.green.shade100,
                    child: const Icon(
                      Icons.check_circle,
                      color: Colors.green,
                      size: 45,
                    ),
                  ),

                  const SizedBox(height: 16),

                  Text(
                    history.status,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 6),

                  Text(
                    history.timestamp.toString(),
                    style: const TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 22),

            _buildTile(
              Icons.people,
              "Recipients",
              history.recipients.join(", "),
            ),

            _buildTile(
              Icons.location_on,
              "Latitude",
              history.latitude.toString(),
            ),

            _buildTile(
              Icons.location_on_outlined,
              "Longitude",
              history.longitude.toString(),
            ),

            _buildTile(Icons.sms, "Emergency Message", history.message),

            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              height: 55,

              child: FilledButton.icon(
                onPressed: () {},

                icon: const Icon(Icons.map),

                label: const Text("Open Google Maps"),
              ),
            ),

            const SizedBox(height: 14),

            SizedBox(
              width: double.infinity,
              height: 55,

              child: OutlinedButton.icon(
                onPressed: () {},

                icon: const Icon(Icons.share),

                label: const Text("Share Incident"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
