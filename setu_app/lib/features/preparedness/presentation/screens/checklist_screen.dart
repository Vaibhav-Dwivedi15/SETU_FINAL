import 'package:flutter/material.dart';

import 'package:setu_app/core/design_system/app_colors.dart';
import 'package:setu_app/core/design_system/app_spacing.dart';
import 'package:setu_app/core/design_system/app_typography.dart';
import 'package:setu_app/core/design_system/widgets/design_system_widgets.dart';
import 'package:setu_app/core/widgets/theme_colors.dart';

import '../../data/models/checklist.dart';
import '../../data/repositories/checklist_repository.dart';

/// One persistent checklist -- used for the Emergency Kit and for each
/// safety checklist. Ticks are saved immediately; progress is shown as a
/// bar and as "x of y done, z remaining".
class ChecklistScreen extends StatefulWidget {
  const ChecklistScreen({super.key, required this.checklistId, this.repository});

  final String checklistId;
  final ChecklistRepository? repository;

  @override
  State<ChecklistScreen> createState() => _ChecklistScreenState();
}

class _ChecklistScreenState extends State<ChecklistScreen> {
  late final ChecklistRepository _repository = widget.repository ?? ChecklistRepository();
  ChecklistProgress? _progress;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final progress = await _repository.progressFor(widget.checklistId);
    if (!mounted) return;
    setState(() {
      _progress = progress;
      _loading = false;
    });
  }

  Future<void> _toggle(ChecklistItem item, bool done) async {
    await _repository.setItemDone(widget.checklistId, item.id, done);
    await _refresh();
  }

  Future<void> _reset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset checklist?'),
        content: const Text('All items will be marked as not done.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Reset')),
        ],
      ),
    );
    if (confirmed != true) return;
    await _repository.reset(widget.checklistId);
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final progress = _progress;
    return Scaffold(
      backgroundColor: context.screenBackground,
      appBar: AppBar(
        title: Text(progress?.checklist.title ?? 'Checklist'),
        centerTitle: true,
        actions: [
          if (progress != null && progress.completed > 0)
            IconButton(
              tooltip: 'Reset checklist',
              icon: const Icon(Icons.restart_alt_rounded),
              onPressed: _reset,
            ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : progress == null
                ? const SetuEmptyState(
                    icon: Icons.error_outline_rounded,
                    title: 'Checklist not found',
                    description: 'This checklist could not be loaded.',
                  )
                : ListView(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    children: [
                      _ProgressHeader(progress: progress),
                      const SizedBox(height: AppSpacing.md),
                      for (final entry in progress.checklist.itemsByCategory.entries) ...[
                        if (entry.key != null) SetuSectionHeader(title: entry.key!),
                        for (final item in entry.value)
                          CheckboxListTile(
                            key: ValueKey(item.id),
                            value: progress.isDone(item),
                            onChanged: (v) => _toggle(item, v ?? false),
                            controlAffinity: ListTileControlAffinity.leading,
                            contentPadding: EdgeInsets.zero,
                            title: Text(item.text,
                                style: AppTypography.body.copyWith(
                                  color: context.textPrimaryColor,
                                  decoration: progress.isDone(item)
                                      ? TextDecoration.lineThrough
                                      : null,
                                )),
                          ),
                      ],
                      const SizedBox(height: AppSpacing.md),
                      if (progress.completed > 0)
                        SetuButton(
                          label: 'Reset checklist',
                          icon: Icons.restart_alt_rounded,
                          variant: SetuButtonVariant.outlined,
                          onPressed: _reset,
                        ),
                    ],
                  ),
      ),
    );
  }
}

class _ProgressHeader extends StatelessWidget {
  const _ProgressHeader({required this.progress});

  final ChecklistProgress progress;

  @override
  Widget build(BuildContext context) {
    final summary = '${progress.completed} of ${progress.total} done · '
        '${progress.remaining} remaining';
    return Semantics(
      container: true,
      label: 'Progress: $summary',
      excludeSemantics: true,
      child: SetuCard(
        padding: const EdgeInsets.all(AppSpacing.md),
        accentBorderLeft: progress.isComplete ? AppColors.success : AppColors.accent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(progress.isComplete ? 'All done' : summary,
                style: AppTypography.cardTitle.copyWith(color: context.textPrimaryColor)),
            const SizedBox(height: AppSpacing.sm),
            LinearProgressIndicator(
              value: progress.fraction,
              minHeight: 8,
              color: progress.isComplete ? AppColors.success : AppColors.accent,
            ),
            if (progress.checklist.description.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(progress.checklist.description,
                  style: AppTypography.caption.copyWith(color: context.textSecondaryColor)),
            ],
          ],
        ),
      ),
    );
  }
}
