// =====================================================
// SETU Project
// Module : Lost Child Alert (UI-only)
// Owner  : Sudheer
// =====================================================
//
// PHASE 1 SCOPE NOTE:
// "I've Seen This Child" / "Not Seen" are stub callbacks —
// no backend call, no packet sent. Real sighting-report
// flow needs a backend contract (Ayush's chat) and team-lead
// sign-off, same as volunteer response tracking.

import 'package:flutter/material.dart';

import 'package:setu_app/core/constants/app_colors.dart';

import '../../data/models/lost_child_alert_model.dart';

class LostChildAlertCard extends StatelessWidget {
  final LostChildAlertModel alert;
  final VoidCallback? onSighted;
  final VoidCallback? onNotSeen;

  const LostChildAlertCard({
    super.key,
    required this.alert,
    this.onSighted,
    this.onNotSeen,
  });

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
                  height: 40,
                  width: 40,
                  decoration: const BoxDecoration(
                    gradient: AppColors.alertGradient,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.campaign,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.alert.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'LOST CHILD',
                    style: TextStyle(
                      color: AppColors.alertDark,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              '${alert.childName}, age ${alert.age}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),

            _infoRow('Description', alert.description),
            const SizedBox(height: 8),
            _infoRow('Last Seen At', alert.lastSeenLocation),
            const SizedBox(height: 8),
            _infoRow('Last Seen Time', _formatTime(alert.lastSeenTime)),
            const SizedBox(height: 8),
            _infoRow('Guardian Contact', alert.guardianContact),

            const SizedBox(height: 18),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onNotSeen,
                    child: const Text('Not Seen'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.alert,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: onSighted,
                    child: const Text("I've Seen This Child"),
                  ),
                ),
              ],
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
          width: 120,
          child: Text(label, style: const TextStyle(color: Colors.grey)),
        ),
        Expanded(
          child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}
