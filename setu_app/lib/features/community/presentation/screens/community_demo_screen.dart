// =====================================================
// SETU Project
// Module : Community / Demo Preview (UI-only)
// Owner  : Sudheer
// =====================================================
//
// Temporary demo/preview screen so both new widgets are
// reachable and testable in a running build before real
// trigger points (radius matching, exit-node upload
// callback) exist. Safe to delete or repurpose once those
// Phase 2 integrations land.

import 'package:flutter/material.dart';

import '../../data/models/volunteer_alert_model.dart';
import '../widgets/humanity_score_popup.dart';
import '../widgets/volunteer_notification_card.dart';

class CommunityDemoScreen extends StatelessWidget {
  const CommunityDemoScreen({super.key});

  void _showVolunteerAlert(BuildContext context) {
    final mockAlert = VolunteerAlertModel(
      incidentType: 'Road Accident',
      distanceKm: 1.4,
      timestamp: DateTime.now(),
      priority: 'high',
      emergencyContact: '+91 98765 43210',
      latitude: 28.6139,
      longitude: 77.2090,
    );

    showDialog(
      context: context,
      builder: (_) => VolunteerNotificationCard(
        alert: mockAlert,
        onAccept: () {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Accepted (stub — no backend call yet)')),
          );
        },
        onIgnore: () {
          Navigator.pop(context);
        },
        onAlreadyHelping: () {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Marked as already helping (stub)')),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Community Features (Demo)')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Preview only — mock data, no real backend or radius '
              'matching yet (Phase 2).',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              icon: const Icon(Icons.volunteer_activism),
              label: const Text('Simulate Volunteer Alert'),
              onPressed: () => _showVolunteerAlert(context),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              icon: const Icon(Icons.favorite),
              label: const Text('Simulate Humanity Score Popup'),
              onPressed: () => HumanityScorePopup.show(context, contributionCount: 1),
            ),
          ],
        ),
      ),
    );
  }
}
