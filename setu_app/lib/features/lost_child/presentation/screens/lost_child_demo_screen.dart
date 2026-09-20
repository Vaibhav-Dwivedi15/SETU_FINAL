// =====================================================
// SETU Project
// Module : Lost Child Alert (UI-only)
// Owner  : Sudheer
// =====================================================
//
// Temporary demo/preview screen, same purpose as
// community_demo_screen.dart — safe to delete or fold
// elsewhere once real trigger points exist.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/lost_child_alert_model.dart';
import '../widgets/lost_child_alert_card.dart';

class LostChildDemoScreen extends StatelessWidget {
  const LostChildDemoScreen({super.key});

  void _previewVolunteerCard(BuildContext context) {
    final mockAlert = LostChildAlertModel(
      childName: 'Aarav Sharma',
      age: 7,
      description: 'Wearing a blue school uniform, red backpack',
      lastSeenLocation: 'Near City Park, Gate 2',
      lastSeenTime: DateTime.now(),
      guardianContact: '+91 98765 43210',
    );

    showDialog(
      context: context,
      builder: (_) => LostChildAlertCard(
        alert: mockAlert,
        onSighted: () {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Marked as sighted (stub)')),
          );
        },
        onNotSeen: () => Navigator.pop(context),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Lost Child Alert (Demo)')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Preview only — broadcast is not actually sent yet '
              '(needs a new mesh packet type, Phase 2).',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              icon: const Icon(Icons.campaign),
              label: const Text('Compose Lost Child Alert'),
              onPressed: () => context.push('/lost-child/broadcast'),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              icon: const Icon(Icons.visibility),
              label: const Text('Preview Volunteer Alert Card'),
              onPressed: () => _previewVolunteerCard(context),
            ),
          ],
        ),
      ),
    );
  }
}
