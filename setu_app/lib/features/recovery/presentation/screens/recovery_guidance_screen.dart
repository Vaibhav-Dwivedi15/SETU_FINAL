import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:setu_app/core/design_system/app_spacing.dart';
import 'package:setu_app/core/design_system/widgets/design_system_widgets.dart';
import 'package:setu_app/core/widgets/theme_colors.dart';
import 'package:setu_app/features/preparedness/data/models/safety_guide_model.dart';
import 'package:setu_app/features/preparedness/data/services/preparedness_service.dart';
import 'package:setu_app/features/preparedness/presentation/widgets/guide_list_tile.dart';

import '../../data/services/recovery_guidance_service.dart';

/// Offline recovery guidance topics. Each opens the shared guide detail
/// screen, reading from the recovery library.
class RecoveryGuidanceScreen extends StatelessWidget {
  const RecoveryGuidanceScreen({super.key, this.library});

  final GuideLibrary? library;

  @override
  Widget build(BuildContext context) {
    final guides = library ?? RecoveryGuidanceService.instance;
    return Scaffold(
      backgroundColor: context.screenBackground,
      appBar: AppBar(title: const Text('Recovery guidance'), centerTitle: true),
      body: SafeArea(
        child: FutureBuilder<List<SafetyGuideModel>>(
          future: guides.loadGuides(),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final topics = snapshot.data ?? const [];
            if (topics.isEmpty) {
              return const SetuEmptyState(
                icon: Icons.menu_book_rounded,
                title: 'Guidance unavailable',
                description: 'No recovery guidance was found on this installation.',
              );
            }
            return ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                for (final topic in topics)
                  GuideListTile(
                    guide: topic,
                    icon: Icons.fact_check_outlined,
                    onTap: () => context.push('/recovery/guidance/${topic.id}'),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
