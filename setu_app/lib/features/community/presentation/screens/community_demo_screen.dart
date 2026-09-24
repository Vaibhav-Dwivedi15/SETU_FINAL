// =====================================================
// SETU Project
// Module : Community / Demo Preview (Redesign)
// =====================================================

import 'package:flutter/material.dart';

import 'package:setu_app/core/design_system/app_colors.dart';
import 'package:setu_app/core/design_system/app_radius.dart';
import 'package:setu_app/core/design_system/app_spacing.dart';
import 'package:setu_app/core/design_system/app_typography.dart';
import 'package:setu_app/core/design_system/widgets/design_system_widgets.dart';

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
            const SnackBar(content: Text('Accepted volunteer dispatch')),
          );
        },
        onIgnore: () {
          Navigator.pop(context);
        },
        onAlreadyHelping: () {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Marked as already responding')),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.bgApp : AppColors.lightBackground,
      appBar: AppBar(
        title: const Text('Community Responders (Demo)'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SetuCard(
                padding: const EdgeInsets.all(AppSpacing.md),
                backgroundColor: isDark ? AppColors.bgSurfaceAlt : AppColors.lightSurface,
                accentBorderLeft: AppColors.community,
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.community.withValues(alpha: 0.14),
                        borderRadius: AppRadius.smRadius,
                      ),
                      child: const Icon(
                        Icons.volunteer_activism_rounded,
                        color: AppColors.community,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Civic Responder Simulation',
                            style: AppTypography.cardTitle.copyWith(
                              color: isDark ? AppColors.textPrimary : AppColors.lightTextPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Preview the peer-to-peer volunteer alert cards and civic humanity score mechanisms.',
                            style: AppTypography.caption.copyWith(
                              color: isDark ? AppColors.textSecondary : AppColors.lightTextSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: AppSpacing.xl),

              SetuButton(
                label: 'SIMULATE VOLUNTEER ALERT',
                icon: Icons.notifications_active_rounded,
                onPressed: () => _showVolunteerAlert(context),
                variant: SetuButtonVariant.primary,
                size: SetuButtonSize.lg,
              ),

              const SizedBox(height: AppSpacing.md),

              SetuButton(
                label: 'SIMULATE HUMANITY SCORE POPUP',
                icon: Icons.favorite_rounded,
                onPressed: () => HumanityScorePopup.show(context, contributionCount: 1),
                variant: SetuButtonVariant.secondary,
                size: SetuButtonSize.lg,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
