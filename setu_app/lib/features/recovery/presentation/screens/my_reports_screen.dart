import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:setu_app/core/design_system/app_spacing.dart';
import 'package:setu_app/core/design_system/widgets/design_system_widgets.dart';
import 'package:setu_app/core/widgets/theme_colors.dart';

import '../../data/models/recovery_record.dart';
import '../../data/models/recovery_report_type.dart';
import '../../data/repositories/recovery_repository.dart';
import '../widgets/report_card.dart';

/// The unified recovery history: every damage report, missing-person
/// report and resource request saved on this device, filterable by kind.
/// Separate from SOS History, which is untouched.
class MyReportsScreen extends StatefulWidget {
  const MyReportsScreen({super.key, this.repository});

  final RecoveryRepository? repository;

  @override
  State<MyReportsScreen> createState() => _MyReportsScreenState();
}

class _MyReportsScreenState extends State<MyReportsScreen> {
  late final RecoveryRepository _repository = widget.repository ?? RecoveryRepository();
  late Future<List<RecoveryRecord>> _reports = _repository.list();
  RecoveryReportType? _filter;

  void _reload() => setState(() {
      _reports = _repository.list();
    });

  Future<void> _openReport(RecoveryRecord record) async {
    await context.push<Object?>('/recovery/reports/${record.id}');
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.screenBackground,
      appBar: AppBar(title: const Text('My reports'), centerTitle: true),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  children: [
                    ChoiceChip(
                      label: const Text('All'),
                      selected: _filter == null,
                      onSelected: (_) => setState(() => _filter = null),
                      materialTapTargetSize: MaterialTapTargetSize.padded,
                    ),
                    for (final type in RecoveryReportType.values)
                      ChoiceChip(
                        label: Text(type.filterLabel),
                        selected: _filter == type,
                        onSelected: (_) => setState(() => _filter = type),
                        materialTapTargetSize: MaterialTapTargetSize.padded,
                      ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: FutureBuilder<List<RecoveryRecord>>(
                future: _reports,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final all = snapshot.data ?? const [];
                  final shown = RecoveryRepository.filter(all, _filter);
                  if (shown.isEmpty) {
                    return SetuEmptyState(
                      icon: Icons.assignment_outlined,
                      title: 'No recovery reports yet.',
                      description: all.isEmpty
                          ? 'Reports you create appear here, even without internet.'
                          : 'No reports of this kind. Choose All to see the rest.',
                    );
                  }
                  return RefreshIndicator(
                    onRefresh: () async => _reload(),
                    child: ListView(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      children: [
                        for (final record in shown)
                          ReportCard(record: record, onTap: () => _openReport(record)),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
