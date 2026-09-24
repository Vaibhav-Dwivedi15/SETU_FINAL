// =====================================================
// SETU Project
// Module : Lost Child Alert (Redesign)
// =====================================================

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:setu_app/core/design_system/app_colors.dart';
import 'package:setu_app/core/design_system/app_radius.dart';
import 'package:setu_app/core/design_system/app_spacing.dart';
import 'package:setu_app/core/design_system/app_typography.dart';
import 'package:setu_app/core/design_system/widgets/design_system_widgets.dart';

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
            const SnackBar(content: Text('Marked as sighted (Demo stub)')),
          );
        },
        onNotSeen: () => Navigator.pop(context),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.bgApp : AppColors.lightBackground,
      appBar: AppBar(
        title: const Text('Lost Child Mesh Broadcast'),
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
                accentBorderLeft: AppColors.accent,
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.14),
                        borderRadius: AppRadius.smRadius,
                      ),
                      child: const Icon(Icons.campaign_rounded, color: AppColors.accent, size: 22),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'High-Priority Mesh Broadcast',
                            style: AppTypography.cardTitle.copyWith(
                              color: isDark ? AppColors.textPrimary : AppColors.lightTextPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Enables rapid local dissemination of missing child physical descriptors to nearby volunteers.',
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
                label: 'COMPOSE CHILD ALERT',
                icon: Icons.campaign_rounded,
                onPressed: () => context.push('/lost-child/broadcast'),
                variant: SetuButtonVariant.primary,
                size: SetuButtonSize.lg,
              ),

              const SizedBox(height: AppSpacing.md),

              SetuButton(
                label: 'PREVIEW VOLUNTEER ALERT CARD',
                icon: Icons.visibility_rounded,
                onPressed: () => _previewVolunteerCard(context),
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
