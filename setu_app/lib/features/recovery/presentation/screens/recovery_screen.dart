import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:setu_app/core/design_system/app_colors.dart';
import 'package:setu_app/core/design_system/app_spacing.dart';
import 'package:setu_app/core/design_system/app_typography.dart';
import 'package:setu_app/core/design_system/widgets/design_system_widgets.dart';
import 'package:setu_app/core/widgets/hub_tile.dart';
import 'package:setu_app/core/widgets/theme_colors.dart';

import '../../data/models/recovery_record.dart';
import '../../data/models/report_status.dart';
import '../../data/repositories/recovery_repository.dart';

/// Recovery Home: entry points for the report forms, guidance and the
/// unified My Reports list.
class RecoveryScreen extends StatefulWidget {
  const RecoveryScreen({super.key, this.repository});

  final RecoveryRepository? repository;

  @override
  State<RecoveryScreen> createState() => _RecoveryScreenState();
}

class _RecoveryScreenState extends State<RecoveryScreen> {
  late final RecoveryRepository _repository = widget.repository ?? RecoveryRepository();
  late Future<List<RecoveryRecord>> _reports = _repository.list();

  void _reload() => setState(() {
      _reports = _repository.list();
    });

  Future<void> _open(String location) async {
    await context.push<Object?>(location);
    if (mounted) _reload();
  }

  String _reportsSubtitle(List<RecoveryRecord> reports) {
    if (reports.isEmpty) return 'No recovery reports yet.';
    int count(ReportStatus s) => reports.where((r) => r.status == s).length;
    final parts = <String>['${reports.length} saved'];
    if (count(ReportStatus.draft) > 0) parts.add('${count(ReportStatus.draft)} draft');
    if (count(ReportStatus.pendingSync) > 0) parts.add('${count(ReportStatus.pendingSync)} pending sync');
    if (count(ReportStatus.failed) > 0) parts.add('${count(ReportStatus.failed)} failed');
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.screenBackground,
      appBar: AppBar(title: const Text('Recovery'), centerTitle: true),
      bottomNavigationBar: SetuBottomNavigation(
        currentIndex: 2,
        onTap: (index) {
          switch (index) {
            case 0:
              context.go('/');
            case 1:
              context.push('/preparedness');
            case 2:
              break;
            case 3:
              context.push('/history');
          }
        },
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              SetuCard(
                padding: const EdgeInsets.all(AppSpacing.md),
                accentBorderLeft: AppColors.warning,
                child: Row(
                  children: [
                    const Icon(Icons.cloud_off_rounded, color: AppColors.warning),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Text(
                        'Reports are saved on this device first and sent when '
                        'a route is available. Use SOS for an emergency.',
                        style: AppTypography.caption.copyWith(color: context.textSecondaryColor),
                      ),
                    ),
                  ],
                ),
              ),
              const SetuSectionHeader(title: 'Report'),
              HubTile(
                icon: Icons.domain_disabled,
                title: 'Damage report',
                subtitle: 'Buildings, roads, electricity, water or fire damage',
                onTap: () => _open('/recovery/damage'),
              ),
              HubTile(
                icon: Icons.person_search,
                title: 'Missing person',
                subtitle: 'Report someone missing after a disaster',
                onTap: () => _open('/recovery/missing'),
              ),
              HubTile(
                icon: Icons.volunteer_activism,
                title: 'Help / resource request',
                subtitle: 'Food, water, medical help, shelter or rescue',
                onTap: () => _open('/recovery/request'),
              ),
              const SetuSectionHeader(title: 'Guidance & history'),
              HubTile(
                icon: Icons.fact_check_outlined,
                title: 'Recovery guidance',
                subtitle: 'Safe return, hazards, water, hygiene, documents',
                onTap: () => _open('/recovery/guidance'),
              ),
              FutureBuilder<List<RecoveryRecord>>(
                future: _reports,
                builder: (context, snapshot) => HubTile(
                  icon: Icons.assignment_outlined,
                  title: 'My reports',
                  subtitle: snapshot.hasData ? _reportsSubtitle(snapshot.data!) : 'Loading…',
                  onTap: () => _open('/recovery/reports'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
