import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:setu_app/core/design_system/app_spacing.dart';
import 'package:setu_app/core/design_system/app_typography.dart';
import 'package:setu_app/core/design_system/widgets/design_system_widgets.dart';
import 'package:setu_app/core/widgets/theme_colors.dart';

import '../../data/models/safety_guide_model.dart';
import '../../data/services/preparedness_service.dart';
import '../widgets/guide_list_tile.dart';

/// All bundled guides, disaster guides first. Fully offline.
class DisasterGuidesScreen extends StatelessWidget {
  const DisasterGuidesScreen({super.key, this.library});

  final GuideLibrary? library;

  @override
  Widget build(BuildContext context) {
    final source = library ?? PreparednessService.instance;
    return Scaffold(
      backgroundColor: context.screenBackground,
      appBar: AppBar(title: const Text('Disaster guides'), centerTitle: true),
      body: SafeArea(
        child: FutureBuilder<List<SafetyGuideModel>>(
          future: source.loadGuides(),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final guides = snapshot.data ?? const [];
            if (guides.isEmpty) {
              return const SetuEmptyState(
                icon: Icons.menu_book_rounded,
                title: 'Guides unavailable',
                description: 'No offline safety guides found on this installation.',
              );
            }
            final disasters = guides.where((g) => g.disasterType != null).toList();
            final others = guides.where((g) => g.disasterType == null).toList();
            return ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                Text('Available offline. No internet needed.',
                    style: AppTypography.caption.copyWith(color: context.textSecondaryColor)),
                if (disasters.isNotEmpty) const SetuSectionHeader(title: 'Disasters'),
                for (final g in disasters)
                  GuideListTile(
                    guide: g,
                    icon: g.disasterType!.icon,
                    onTap: () => context.push('/preparedness/guide/${g.id}'),
                  ),
                if (others.isNotEmpty) const SetuSectionHeader(title: 'Other safety guides'),
                for (final g in others)
                  GuideListTile(
                    guide: g,
                    icon: Icons.shield_outlined,
                    onTap: () => context.push('/preparedness/guide/${g.id}'),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
