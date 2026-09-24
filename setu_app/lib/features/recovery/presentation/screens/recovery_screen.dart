// =====================================================
// SETU Project
// Module : Recovery Screen (Redesign)
// =====================================================

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:setu_app/core/design_system/app_colors.dart';
import 'package:setu_app/core/design_system/app_radius.dart';
import 'package:setu_app/core/design_system/app_spacing.dart';
import 'package:setu_app/core/design_system/app_typography.dart';
import 'package:setu_app/core/design_system/widgets/design_system_widgets.dart';

import '../../data/models/recovery_report_model.dart';
import '../../data/models/recovery_report_type.dart';
import '../../data/repositories/recovery_repository.dart';

class RecoveryScreen extends StatefulWidget {
  const RecoveryScreen({super.key});

  @override
  State<RecoveryScreen> createState() => _RecoveryScreenState();
}

class _RecoveryScreenState extends State<RecoveryScreen> {
  final _repository = RecoveryRepository();
  late Future<List<RecoveryReportModel>> _reports;

  @override
  void initState() {
    super.initState();
    _reports = _repository.getReports();
  }

  void _reload() {
    setState(() {
      _reports = _repository.getReports();
    });
  }

  Future<void> _openForm(RecoveryReportType type) async {
    final sent = await context.push<bool>('/recovery/report', extra: type);
    if (sent == true) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.bgApp : AppColors.lightBackground,
      appBar: AppBar(
        title: const Text('Recovery & Reporting'),
        centerTitle: true,
      ),
      bottomNavigationBar: SetuBottomNavigation(
        currentIndex: 2,
        onTap: (index) {
          switch (index) {
            case 0:
              context.go('/');
              break;
            case 1:
              context.push('/preparedness');
              break;
            case 2:
              // Already here
              break;
            case 3:
              context.push('/history');
              break;
          }
        },
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              // Header description
              SetuCard(
                padding: const EdgeInsets.all(AppSpacing.md),
                backgroundColor: isDark ? AppColors.bgSurfaceAlt : AppColors.lightSurface,
                accentBorderLeft: AppColors.warning,
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha: 0.14),
                        borderRadius: AppRadius.smRadius,
                      ),
                      child: const Icon(Icons.restore_rounded, color: AppColors.warning, size: 24),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Post-Incident Coordination',
                            style: AppTypography.cardTitle.copyWith(
                              color: isDark ? AppColors.textPrimary : AppColors.lightTextPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Broadcast damage assessments, missing person alerts, and resource availability over the mesh.',
                            style: AppTypography.caption.copyWith(
                              color: isDark ? AppColors.textSecondary : AppColors.lightTextSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: AppSpacing.lg),

              const SetuSectionHeader(
                title: 'File a Report',
                subtitle: 'Dispatches signed emergency recovery packets',
                padding: EdgeInsets.only(bottom: AppSpacing.sm),
              ),

              ...RecoveryReportType.values.map(
                (type) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: SetuCard(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    onTap: () => _openForm(type),
                    child: Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: isDark ? AppColors.bgInput : AppColors.lightBackground,
                            borderRadius: AppRadius.smRadius,
                            border: Border.all(
                              color: isDark ? AppColors.borderSubtle : AppColors.lightBorder,
                            ),
                          ),
                          child: Icon(type.icon, size: 20, color: AppColors.accent),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                type.title,
                                style: AppTypography.cardTitle.copyWith(
                                  color: isDark ? AppColors.textPrimary : AppColors.lightTextPrimary,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 1),
                              Text(
                                type.subtitle,
                                style: AppTypography.caption.copyWith(
                                  color: isDark ? AppColors.textSecondary : AppColors.lightTextSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: isDark ? AppColors.textDim : AppColors.lightTextDim,
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: AppSpacing.lg),

              const SetuSectionHeader(
                title: 'Recent Reports',
                subtitle: 'Packets originated from this device',
                padding: EdgeInsets.only(bottom: AppSpacing.sm),
              ),

              FutureBuilder<List<RecoveryReportModel>>(
                future: _reports,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 32),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final reports = snapshot.data ?? const [];
                  if (reports.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: SetuEmptyState(
                        icon: Icons.assignment_outlined,
                        title: 'No Reports Filed',
                        description: 'You have not submitted any recovery reports yet.',
                      ),
                    );
                  }
                  return Column(
                    children: reports.map(
                      (report) => Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                        child: SetuCard(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(report.type.icon, size: 16, color: AppColors.accent),
                                  const SizedBox(width: 6),
                                  Text(
                                    report.type.title,
                                    style: AppTypography.cardTitle.copyWith(
                                      color: isDark ? AppColors.textPrimary : AppColors.lightTextPrimary,
                                      fontSize: 13.5,
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    _formatTimestamp(report.timestamp),
                                    style: AppTypography.metadata.copyWith(
                                      color: isDark ? AppColors.textDim : AppColors.lightTextDim,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                report.message,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.body.copyWith(
                                  color: isDark ? AppColors.textSecondary : AppColors.lightTextSecondary,
                                  fontSize: 13.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ).toList(),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final local = timestamp.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '${local.day}/${local.month} $hh:$mm';
  }
}
