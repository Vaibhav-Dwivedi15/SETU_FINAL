// =====================================================
// SETU Project
// Module : Safety Guide Detail Screen (Redesign)
// =====================================================

import 'package:flutter/material.dart';

import 'package:setu_app/core/design_system/app_colors.dart';
import 'package:setu_app/core/design_system/app_radius.dart';
import 'package:setu_app/core/design_system/app_spacing.dart';
import 'package:setu_app/core/design_system/app_typography.dart';
import 'package:setu_app/core/design_system/widgets/design_system_widgets.dart';

import '../../data/models/safety_guide_model.dart';
import '../../data/services/preparedness_service.dart';

class SafetyGuideDetailScreen extends StatelessWidget {
  const SafetyGuideDetailScreen({super.key, required this.guideId});

  final String guideId;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.bgApp : AppColors.lightBackground,
      body: FutureBuilder<SafetyGuideModel?>(
        future: PreparednessService.instance.guideById(guideId),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final guide = snapshot.data;
          if (guide == null) {
            return Scaffold(
              appBar: AppBar(title: const Text('Not available')),
              body: const SetuEmptyState(
                icon: Icons.error_outline_rounded,
                title: 'Guide Not Found',
                description: 'This offline guide could not be loaded.',
              ),
            );
          }

          return CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverAppBar(
                title: Text(guide.title),
                centerTitle: true,
                floating: true,
                pinned: true,
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Guide Summary Card
                      SetuCard(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        backgroundColor: isDark
                            ? AppColors.bgSurfaceAlt
                            : AppColors.lightSurface,
                        accentBorderLeft: AppColors.accent,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.shield_outlined,
                                  color: AppColors.accent,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'EMERGENCY PROTOCOL',
                                  style: AppTypography.metadata.copyWith(
                                    color: AppColors.accent,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              guide.summary,
                              style: AppTypography.body.copyWith(
                                color: isDark
                                    ? AppColors.textPrimary
                                    : AppColors.lightTextPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: AppSpacing.lg),

                      const SetuSectionHeader(
                        title: 'Action Steps',
                        subtitle: 'Follow in order during an active event',
                        padding: EdgeInsets.only(bottom: AppSpacing.sm),
                      ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  0,
                  AppSpacing.lg,
                  AppSpacing.xl,
                ),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final stepNumber = index + 1;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: SetuCard(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? AppColors.bgInput
                                      : AppColors.lightBackground,
                                  borderRadius: AppRadius.smRadius,
                                  border: Border.all(
                                    color: isDark
                                        ? AppColors.borderSubtle
                                        : AppColors.lightBorder,
                                  ),
                                ),
                                child: Center(
                                  child: Text(
                                    '$stepNumber',
                                    style: AppTypography.metadata.copyWith(
                                      color: AppColors.accent,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.md),
                              Expanded(
                                child: Text(
                                  guide.steps[index],
                                  style: AppTypography.body.copyWith(
                                    color: isDark
                                        ? AppColors.textPrimary
                                        : AppColors.lightTextPrimary,
                                    height: 1.45,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                    childCount: guide.steps.length,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
