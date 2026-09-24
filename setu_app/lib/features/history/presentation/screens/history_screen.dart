// =====================================================
// SETU Project
// Module : History Screen (Redesign)
// =====================================================

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:setu_app/core/design_system/app_colors.dart';
import 'package:setu_app/core/design_system/app_radius.dart';
import 'package:setu_app/core/design_system/app_spacing.dart';
import 'package:setu_app/core/design_system/app_typography.dart';
import 'package:setu_app/core/design_system/widgets/design_system_widgets.dart';

import '../../data/models/history_model.dart';
import '../../data/repositories/history_repository.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final HistoryRepository _repository = HistoryRepository();

  List<HistoryModel> _history = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() {
      _isLoading = true;
    });

    _history = await _repository.getHistory();

    if (!mounted) return;
    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _openGoogleMaps(String mapsLink) async {
    final Uri uri = Uri.parse(mapsLink);

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Unable to open map application")),
      );
    }
  }

  Future<void> _refresh() async {
    await _loadHistory();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.bgApp : AppColors.lightBackground,
      appBar: AppBar(
        title: const Text("Emergency Dispatch Log"),
        centerTitle: true,
      ),
      bottomNavigationBar: SetuBottomNavigation(
        currentIndex: 3,
        onTap: (index) {
          switch (index) {
            case 0:
              context.go('/');
              break;
            case 1:
              context.push('/preparedness');
              break;
            case 2:
              context.push('/recovery');
              break;
            case 3:
              // Already here
              break;
          }
        },
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _history.isEmpty
                  ? const SetuEmptyState(
                      icon: Icons.history_rounded,
                      title: "No Emergency History",
                      description:
                          "Every distress beacon and recovery packet originated from this device will be logged here.",
                    )
                  : ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(
                        parent: BouncingScrollPhysics(),
                      ),
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      itemCount: _history.length,
                      itemBuilder: (context, index) {
                        final item = _history[index];
                        return _buildHistoryCard(item, isDark);
                      },
                    ),
        ),
      ),
    );
  }

  Widget _buildHistoryCard(HistoryModel item, bool isDark) {
    final isDelivered = item.status.toLowerCase() == 'delivered';
    final isSent = item.status.toLowerCase() == 'sent';

    final SetuIncidentState incidentState = isDelivered
        ? SetuIncidentState.delivered
        : (isSent ? SetuIncidentState.pending : SetuIncidentState.failed);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: SetuCard(
        padding: const EdgeInsets.all(AppSpacing.md),
        accentBorderLeft: isDelivered
            ? AppColors.success
            : (isSent ? AppColors.accent : AppColors.emergency),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SetuIncidentStatusBadge(
                  state: incidentState,
                  customLabel: isSent ? 'SENT · AWAITING ACK' : null,
                ),
                const Spacer(),
                Text(
                  _formatTimestamp(item.timestamp),
                  style: AppTypography.metadata.copyWith(
                    color: isDark ? AppColors.textDim : AppColors.lightTextDim,
                    fontSize: 11,
                  ),
                ),
              ],
            ),

            const SizedBox(height: AppSpacing.sm),

            Row(
              children: [
                Icon(
                  Icons.people_outline_rounded,
                  size: 16,
                  color: isDark ? AppColors.textDim : AppColors.lightTextDim,
                ),
                const SizedBox(width: 6),
                Text(
                  "${item.recipients.length} Recipient Contact(s)",
                  style: AppTypography.bodyStrong.copyWith(
                    color: isDark
                        ? AppColors.textPrimary
                        : AppColors.lightTextPrimary,
                    fontSize: 13.5,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 4),

            Row(
              children: [
                Icon(
                  Icons.location_on_outlined,
                  size: 16,
                  color: isDark ? AppColors.textDim : AppColors.lightTextDim,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    "Coordinates: ${item.latitude.toStringAsFixed(4)}, ${item.longitude.toStringAsFixed(4)}",
                    style: AppTypography.caption.copyWith(
                      color: isDark
                          ? AppColors.textSecondary
                          : AppColors.lightTextSecondary,
                    ),
                  ),
                ),
                if (item.mapsLink.isNotEmpty)
                  InkWell(
                    onTap: () => _openGoogleMaps(item.mapsLink),
                    borderRadius: AppRadius.smRadius,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            "View Map",
                            style: AppTypography.metadata.copyWith(
                              color: AppColors.accent,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 2),
                          const Icon(
                            Icons.open_in_new_rounded,
                            size: 13,
                            color: AppColors.accent,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),

            if (item.errorReason.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                "Error: ${item.errorReason}",
                style: AppTypography.caption.copyWith(
                  color: AppColors.emergency,
                  fontSize: 11.5,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final local = timestamp.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '${local.day}/${local.month}/${local.year} $hh:$mm';
  }
}
