// =====================================================
// SETU Project
// Module : Preparedness Screen (Redesign)
// =====================================================

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:setu_app/core/design_system/app_colors.dart';
import 'package:setu_app/core/design_system/app_radius.dart';
import 'package:setu_app/core/design_system/app_spacing.dart';
import 'package:setu_app/core/design_system/app_typography.dart';
import 'package:setu_app/core/design_system/widgets/design_system_widgets.dart';

import '../../data/models/safety_guide_model.dart';
import '../../data/services/preparedness_service.dart';

class PreparednessScreen extends StatefulWidget {
  const PreparednessScreen({super.key});

  @override
  State<PreparednessScreen> createState() => _PreparednessScreenState();
}

class _PreparednessScreenState extends State<PreparednessScreen> {
  late final Future<List<SafetyGuideModel>> _guides;

  @override
  void initState() {
    super.initState();
    _guides = PreparednessService.instance.loadGuides();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.bgApp : AppColors.lightBackground,
      appBar: AppBar(
        title: const Text('Preparedness Hub'),
        centerTitle: true,
      ),
      bottomNavigationBar: SetuBottomNavigation(
        currentIndex: 1,
        onTap: (index) {
          switch (index) {
            case 0:
              context.go('/');
              break;
            case 1:
              // Already here
              break;
            case 2:
              context.push('/recovery');
              break;
            case 3:
              context.push('/history');
              break;
          }
        },
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            // Readiness Check hero card
            SetuCard(
              padding: const EdgeInsets.all(AppSpacing.md),
              onTap: () => context.push('/preparedness/readiness'),
              accentBorderLeft: AppColors.accent,
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.14),
                      borderRadius: AppRadius.smRadius,
                    ),
                    child: const Icon(
                      Icons.checklist_rtl_rounded,
                      color: AppColors.accent,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Device Readiness Check',
                                style: AppTypography.cardTitle.copyWith(
                                  color: isDark
                                      ? AppColors.textPrimary
                                      : AppColors.lightTextPrimary,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.accent.withValues(alpha: 0.15),
                                borderRadius: AppRadius.pillRadius,
                              ),
                              child: Text(
                                'DIAGNOSTIC',
                                style: AppTypography.metadata.copyWith(
                                  color: AppColors.accent,
                                  fontSize: 9.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Test Bluetooth, Location, Wi-Fi and Mesh permissions before emergencies occur.',
                          style: AppTypography.caption.copyWith(
                            color: isDark
                                ? AppColors.textSecondary
                                : AppColors.lightTextSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: isDark ? AppColors.textDim : AppColors.lightTextDim,
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.lg),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const SetuSectionHeader(
                  title: 'Emergency Guides',
                  subtitle: 'Actionable protocols for offline use',
                  padding: EdgeInsets.zero,
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.12),
                    borderRadius: AppRadius.pillRadius,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.download_done_rounded, size: 12, color: AppColors.success),
                      const SizedBox(width: 4),
                      Text(
                        '100% OFFLINE',
                        style: AppTypography.metadata.copyWith(
                          color: AppColors.success,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: AppSpacing.sm),

            FutureBuilder<List<SafetyGuideModel>>(
              future: _guides,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(
                      child: CircularProgressIndicator(),
                    ),
                  );
                }

                final guides = snapshot.data ?? const [];
                if (guides.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: SetuEmptyState(
                      icon: Icons.menu_book_rounded,
                      title: 'Guides Unavailable',
                      description: 'No offline safety guides found on this installation.',
                    ),
                  );
                }

                return Column(
                  children: guides.map((guide) {
                    final icon = _iconFor(guide.id);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: SetuCard(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        onTap: () => context.push('/preparedness/guide/${guide.id}'),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: isDark
                                    ? AppColors.bgSurfaceAlt
                                    : AppColors.lightBackground,
                                borderRadius: AppRadius.smRadius,
                                border: Border.all(
                                  color: isDark
                                      ? AppColors.borderSubtle
                                      : AppColors.lightBorder,
                                ),
                              ),
                              child: Icon(
                                icon,
                                size: 20,
                                color: AppColors.accent,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    guide.title,
                                    style: AppTypography.cardTitle.copyWith(
                                      color: isDark
                                          ? AppColors.textPrimary
                                          : AppColors.lightTextPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    guide.summary,
                                    style: AppTypography.caption.copyWith(
                                      color: isDark
                                          ? AppColors.textSecondary
                                          : AppColors.lightTextSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Icon(
                              Icons.chevron_right_rounded,
                              color: isDark ? AppColors.textDim : AppColors.lightTextDim,
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconFor(String id) {
    switch (id) {
      case 'flood':
        return Icons.water_rounded;
      case 'fire':
        return Icons.local_fire_department_rounded;
      case 'earthquake':
        return Icons.vibration_rounded;
      case 'accident':
        return Icons.emergency_rounded;
      case 'women_safety':
        return Icons.shield_rounded;
      case 'child_safety':
        return Icons.child_care_rounded;
      case 'senior_citizen':
        return Icons.elderly_rounded;
      default:
        return Icons.info_outline_rounded;
    }
  }
}
