// =====================================================
// SETU Project
// Module : Community / Volunteer Notification (UI-only)
// Owner  : Sudheer
// =====================================================
//
// PHASE 1 SCOPE NOTE:
// Accept / Ignore / Already Helping are wired to local
// callbacks only (onAccept / onIgnore / onAlreadyHelping).
// There is no backend call here yet — response tracking is
// Phase 2 (needs Ayush + team-lead sign-off on the data
// model). Callers should treat these as stub hooks.

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:setu_app/core/constants/app_colors.dart';

import '../../data/models/volunteer_alert_model.dart';

class VolunteerNotificationCard extends StatelessWidget {
  final VolunteerAlertModel alert;
  final VoidCallback? onAccept;
  final VoidCallback? onIgnore;
  final VoidCallback? onAlreadyHelping;

  const VolunteerNotificationCard({
    super.key,
    required this.alert,
    this.onAccept,
    this.onIgnore,
    this.onAlreadyHelping,
  });

  Color _priorityColor() {
    switch (alert.priority) {
      case 'critical':
        return Colors.red.shade700;
      case 'high':
        return Colors.orange.shade700;
      case 'medium':
        return Colors.amber.shade700;
      default:
        return Colors.green.shade700;
    }
  }

  Future<void> _openNavigation() async {
    final uri = Uri.parse(
      'https://maps.google.com/?q=${alert.latitude},${alert.longitude}',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  String _formatTime(DateTime t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  height: 44,
                  width: 44,
                  decoration: const BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.volunteer_activism,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Someone Nearby Needs Help',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            _infoRow('Incident Type', alert.incidentType),
            const SizedBox(height: 8),
            _infoRow('Distance', '${alert.distanceKm.toStringAsFixed(1)} km away'),
            const SizedBox(height: 8),
            _infoRow('Time', _formatTime(alert.timestamp)),
            const SizedBox(height: 8),
            Row(
              children: [
                const SizedBox(
                  width: 110,
                  child: Text('Priority', style: TextStyle(color: Colors.grey)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _priorityColor().withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    alert.priority.toUpperCase(),
                    style: TextStyle(
                      color: _priorityColor(),
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _infoRow('Emergency Contact', alert.emergencyContact),

            const SizedBox(height: 18),

            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _openNavigation,
                icon: const Icon(Icons.navigation),
                label: const Text('Navigate'),
              ),
            ),

            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onIgnore,
                    child: const Text('Ignore'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: onAlreadyHelping,
                    child: const Text('Already Helping'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
                onPressed: onAccept,
                child: const Text('Accept & Respond'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(label, style: const TextStyle(color: Colors.grey)),
        ),
        Expanded(
          child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}
