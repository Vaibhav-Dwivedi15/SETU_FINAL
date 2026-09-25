import 'package:flutter/material.dart';

import 'package:setu_app/core/design_system/app_colors.dart';
import 'package:setu_app/core/design_system/app_spacing.dart';
import 'package:setu_app/core/design_system/app_typography.dart';
import 'package:setu_app/core/design_system/widgets/design_system_widgets.dart';
import 'package:setu_app/core/widgets/theme_colors.dart';

import '../../data/models/guide_section.dart';
import '../../data/models/safety_guide_model.dart';
import '../../data/services/preparedness_service.dart';

/// Renders one bundled guide: a summary plus its sections (Before /
/// During / After / Avoid for disasters, or a single numbered list for
/// flat guides). Content-driven, so new guides need no screen changes.
class SafetyGuideDetailScreen extends StatelessWidget {
  const SafetyGuideDetailScreen({super.key, required this.guideId, this.library});

  final String guideId;

  /// Defaults to the preparedness guides; the recovery guidance route
  /// passes its own library.
  final GuideLibrary? library;

  @override
  Widget build(BuildContext context) {
    final source = library ?? PreparednessService.instance;
    return FutureBuilder<SafetyGuideModel?>(
      future: source.guideById(guideId),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Scaffold(
            backgroundColor: context.screenBackground,
            appBar: AppBar(),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        final guide = snapshot.data;
        if (guide == null) {
          return Scaffold(
            backgroundColor: context.screenBackground,
            appBar: AppBar(title: const Text('Not available')),
            body: const SetuEmptyState(
              icon: Icons.error_outline_rounded,
              title: 'Guide not found',
              description: 'This offline guide could not be loaded.',
            ),
          );
        }
        return Scaffold(
          backgroundColor: context.screenBackground,
          appBar: AppBar(title: Text(guide.title), centerTitle: true),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                Text(guide.summary,
                    style: AppTypography.body.copyWith(color: context.textSecondaryColor)),
                for (final section in guide.sections) _SectionCard(section: section),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.section});

  final GuideSection section;

  @override
  Widget build(BuildContext context) {
    final isAvoid = section.kind == GuideSectionKind.avoid;
    final numbered = section.kind == GuideSectionKind.steps;
    final accent = isAvoid ? AppColors.emergencyBright : AppColors.accent;

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg),
      child: Semantics(
        container: true,
        label: '${section.kind.title} section',
        child: SetuCard(
          padding: const EdgeInsets.all(AppSpacing.md),
          accentBorderLeft: accent,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(section.kind.icon, size: 20, color: accent),
                  const SizedBox(width: AppSpacing.sm),
                  Text(section.kind.title.toUpperCase(),
                      style: AppTypography.sectionTitle.copyWith(color: accent)),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              for (var i = 0; i < section.items.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 24,
                        child: Text(numbered ? '${i + 1}.' : (isAvoid ? '✕' : '•'),
                            style: AppTypography.body.copyWith(color: accent)),
                      ),
                      Expanded(
                        child: Text(section.items[i],
                            style: AppTypography.body
                                .copyWith(color: context.textPrimaryColor, height: 1.4)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
