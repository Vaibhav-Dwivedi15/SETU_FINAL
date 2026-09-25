import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:setu_app/core/design_system/app_colors.dart';
import 'package:setu_app/core/design_system/app_spacing.dart';
import 'package:setu_app/core/design_system/app_typography.dart';
import 'package:setu_app/core/design_system/widgets/design_system_widgets.dart';
import 'package:setu_app/core/widgets/theme_colors.dart';

import '../../data/models/recovery_record.dart';
import '../../data/models/recovery_report_type.dart';
import '../../data/models/report_status.dart';
import '../../data/repositories/recovery_repository.dart';
import '../widgets/report_presentation.dart';
import '../widgets/report_status_chip.dart';

class ReportDetailScreen extends StatefulWidget {
  const ReportDetailScreen({super.key, required this.reportId, this.repository});

  final String reportId;
  final RecoveryRepository? repository;

  @override
  State<ReportDetailScreen> createState() => _ReportDetailScreenState();
}

class _ReportDetailScreenState extends State<ReportDetailScreen> {
  late final RecoveryRepository _repository = widget.repository ?? RecoveryRepository();
  late Future<RecoveryRecord?> _record = _repository.get(widget.reportId);
  bool _busy = false;

  void _reload() => setState(() {
      _record = _repository.get(widget.reportId);
    });

  String _editRoute(RecoveryRecord r) {
    const paths = {
      RecoveryReportType.damage: '/recovery/damage',
      RecoveryReportType.missingPerson: '/recovery/missing',
      RecoveryReportType.resourceRequest: '/recovery/request',
    };
    return '${paths[r.type]}?draft=${r.id}';
  }

  Future<void> _retry() async {
    setState(() {
      _busy = true;
    });
    try {
      final result = await _repository.retry(widget.reportId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result.status == ReportStatus.failed
            ? 'Sync failed. Report remains saved locally.'
            : 'Report queued. It will sync when connectivity is available.'),
      ));
      _reload();
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this draft?'),
        content: const Text('The draft will be removed from this device.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    await _repository.deleteDraft(widget.reportId);
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.screenBackground,
      appBar: AppBar(title: const Text('Report details'), centerTitle: true),
      body: SafeArea(
        child: FutureBuilder<RecoveryRecord?>(
          future: _record,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final record = snapshot.data;
            if (record == null) {
              return const SetuEmptyState(
                icon: Icons.error_outline_rounded,
                title: 'Report not found',
                description: 'This report is no longer stored on this device.',
              );
            }
            return ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                SetuCard(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(record.type.title,
                                style: AppTypography.cardTitle
                                    .copyWith(color: context.textPrimaryColor)),
                          ),
                          ReportStatusChip(status: record.status),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(record.status.description,
                          style: AppTypography.caption.copyWith(color: context.textSecondaryColor)),
                      if (record.lastError != null) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Text('Last attempt: ${record.lastError}',
                            style: AppTypography.caption
                                .copyWith(color: AppColors.emergencyBright)),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                _row(context, 'Report ID', record.id),
                _row(context, 'Created', formatDateTime(record.createdAt)),
                _row(context, 'Last updated', formatDateTime(record.updatedAt)),
                for (final (label, value) in detailFields(record)) _row(context, label, value),
                const SizedBox(height: AppSpacing.lg),
                if (record.status.isEditable)
                  SetuButton(
                    label: record.status == ReportStatus.draft ? 'Edit draft' : 'Edit report',
                    icon: Icons.edit_rounded,
                    onPressed: _busy
                        ? null
                        : () async {
                            await context.push<Object?>(_editRoute(record));
                            if (mounted) _reload();
                          },
                  ),
                if (record.status.canRetry) ...[
                  const SizedBox(height: AppSpacing.sm),
                  SetuButton(
                    label: 'Retry sync',
                    icon: Icons.sync_rounded,
                    variant: SetuButtonVariant.outlined,
                    isLoading: _busy,
                    onPressed: _busy ? null : _retry,
                  ),
                ],
                if (record.status == ReportStatus.draft) ...[
                  const SizedBox(height: AppSpacing.sm),
                  SetuButton(
                    label: 'Delete draft',
                    icon: Icons.delete_outline_rounded,
                    variant: SetuButtonVariant.ghost,
                    onPressed: _busy ? null : _delete,
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Semantics(
          container: true,
          label: '$label: $value',
          excludeSemantics: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: AppTypography.metadata.copyWith(color: context.textDimColor)),
              Text(value.isEmpty ? '—' : value,
                  style: AppTypography.body.copyWith(color: context.textPrimaryColor)),
            ],
          ),
        ),
      );
}
