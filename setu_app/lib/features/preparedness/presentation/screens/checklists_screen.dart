import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:setu_app/core/design_system/app_spacing.dart';
import 'package:setu_app/core/design_system/widgets/design_system_widgets.dart';
import 'package:setu_app/core/widgets/hub_tile.dart';
import 'package:setu_app/core/widgets/theme_colors.dart';

import '../../data/models/checklist.dart';
import '../../data/repositories/checklist_repository.dart';

/// The safety checklists (everything except the Emergency Kit, which has
/// its own entry on the Prepare hub), each with live progress.
class ChecklistsScreen extends StatefulWidget {
  const ChecklistsScreen({super.key, this.repository});

  final ChecklistRepository? repository;

  @override
  State<ChecklistsScreen> createState() => _ChecklistsScreenState();
}

class _ChecklistsScreenState extends State<ChecklistsScreen> {
  late final ChecklistRepository _repository = widget.repository ?? ChecklistRepository();
  late Future<List<ChecklistProgress>> _all = _repository.allProgress();

  Future<void> _open(String id) async {
    await context.push<Object?>('/preparedness/checklists/$id');
    if (mounted) {
      setState(() {
        _all = _repository.allProgress();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.screenBackground,
      appBar: AppBar(title: const Text('Safety checklists'), centerTitle: true),
      body: SafeArea(
        child: FutureBuilder<List<ChecklistProgress>>(
          future: _all,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final lists = (snapshot.data ?? const [])
                .where((p) => p.checklist.id != ChecklistRepository.kitId)
                .toList();
            if (lists.isEmpty) {
              return const SetuEmptyState(
                icon: Icons.checklist_rounded,
                title: 'Checklists unavailable',
                description: 'No checklists were found on this installation.',
              );
            }
            return ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                for (final p in lists)
                  HubTile(
                    icon: p.isComplete ? Icons.task_alt_rounded : Icons.checklist_rounded,
                    title: p.checklist.title,
                    subtitle: '${p.completed} of ${p.total} done',
                    onTap: () => _open(p.checklist.id),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
