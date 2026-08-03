// =====================================================
// SETU Project
// Module : Community / Humanity Score (UI-only)
// Owner  : Sudheer
// =====================================================
//
// PHASE 1 SCOPE NOTE:
// This is purely a display widget — the acknowledgment an
// Exit Node sees after their device successfully carries an
// emergency report out to connectivity. `contributionCount`
// is passed in by the caller; this widget does NOT calculate
// or persist any score. Actual score logic/storage is
// backend territory (Phase 2, needs team-lead sign-off) —
// do not wire this to SharedPreferences or any local
// "running total" without that conversation happening first.

import 'package:flutter/material.dart';

import 'package:setu_app/core/constants/app_colors.dart';

class HumanityScorePopup extends StatelessWidget {
  final int contributionCount;

  const HumanityScorePopup({super.key, required this.contributionCount});

  static Future<void> show(BuildContext context, {required int contributionCount}) {
    return showDialog(
      context: context,
      builder: (_) => HumanityScorePopup(contributionCount: contributionCount),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                gradient: AppColors.primaryGradient,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.favorite, color: Colors.white, size: 36),
            ),
            const SizedBox(height: 18),
            const Text(
              'Thank You',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              'Because of your device, an emergency report successfully '
              'reached the network.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: Theme.of(context).textTheme.bodyLarge?.color,
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(30),
              ),
              child: Text(
                'Reports carried: $contributionCount',
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
