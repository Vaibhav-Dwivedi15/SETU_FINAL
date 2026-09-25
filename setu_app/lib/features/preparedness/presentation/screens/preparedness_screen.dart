import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:setu_app/core/design_system/app_spacing.dart';
import 'package:setu_app/core/design_system/app_typography.dart';
import 'package:setu_app/core/design_system/widgets/design_system_widgets.dart';
import 'package:setu_app/core/widgets/hub_tile.dart';
import 'package:setu_app/core/widgets/theme_colors.dart';

import '../../data/models/checklist.dart';
import '../../data/repositories/checklist_repository.dart';

/// Prepare Home: entry points for everything a household does BEFORE a
/// disaster. Every destination works offline.
class PreparednessScreen extends StatefulWidget {
  const PreparednessScreen({super.key, this.checklists});

  final ChecklistRepository? checklists;

  @override
  State<PreparednessScreen> createState() => _PreparednessScreenState();
}

class _PreparednessScreenState extends State<PreparednessScreen> {
  late final ChecklistRepository _checklists = widget.checklists ?? ChecklistRepository();
  late Future<List<ChecklistProgress>> _progress = _checklists.allProgress();

  Future<void> _open(String location) async {
    await context.push<Object?>(location);
    if (mounted) {
      setState(() {
        _progress = _checklists.allProgress();
      });
    }
  }

  String _kitSubtitle(List<ChecklistProgress> all) {
    for (final p in all) {
      if (p.checklist.id == ChecklistRepository.kitId) {
        return '${p.completed} of ${p.total} packed';
      }
    }
    return 'Water, food, medicines, torch and documents';
  }

  String _checklistsSubtitle(List<ChecklistProgress> all) {
    final lists = all.where((p) => p.checklist.id != ChecklistRepository.kitId).toList();
    if (lists.isEmpty) return 'Home, evacuation, family and communication';
    final done = lists.fold<int>(0, (sum, p) => sum + p.completed);
    final total = lists.fold<int>(0, (sum, p) => sum + p.total);
    return '$done of $total tasks done';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.screenBackground,
      appBar: AppBar(title: const Text('Prepare'), centerTitle: true),
      bottomNavigationBar: SetuBottomNavigation(
        currentIndex: 1,
        onTap: (index) {
          switch (index) {
            case 0:
              context.go('/');
            case 1:
              break;
            case 2:
              context.push('/recovery');
            case 3:
              context.push('/history');
          }
        },
      ),
      body: SafeArea(
        child: FutureBuilder<List<ChecklistProgress>>(
          future: _progress,
          builder: (context, snapshot) {
            final all = snapshot.data ?? const <ChecklistProgress>[];
            return ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: Text(
                    'Everything in Prepare works without internet.',
                    style: AppTypography.caption.copyWith(color: context.textSecondaryColor),
                  ),
                ),
                HubTile(
                  icon: Icons.menu_book_rounded,
                  title: 'Disaster guides',
                  subtitle: 'Flood, earthquake, cyclone, fire and landslide',
                  onTap: () => _open('/preparedness/guides'),
                ),
                HubTile(
                  icon: Icons.backpack_rounded,
                  title: 'Emergency kit',
                  subtitle: _kitSubtitle(all),
                  onTap: () => _open('/preparedness/kit'),
                ),
                HubTile(
                  icon: Icons.checklist_rounded,
                  title: 'Safety checklists',
                  subtitle: _checklistsSubtitle(all),
                  onTap: () => _open('/preparedness/checklists'),
                ),
                HubTile(
                  icon: Icons.family_restroom_rounded,
                  title: 'Emergency plan',
                  subtitle: 'Contacts, meeting point and notes',
                  onTap: () => _open('/preparedness/plan'),
                ),
                HubTile(
                  icon: Icons.contact_phone_rounded,
                  title: 'Emergency contacts',
                  subtitle: 'People to call, with one-tap dialling',
                  onTap: () => _open('/preparedness/contacts'),
                ),
                HubTile(
                  icon: Icons.settings_input_antenna_rounded,
                  title: 'Device readiness check',
                  subtitle: 'Test Bluetooth, location and mesh permissions',
                  onTap: () => _open('/preparedness/readiness'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
