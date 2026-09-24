// =====================================================
// SETU Project
// Module : Nearby Alerts Screen (Redesign)
// =====================================================

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:setu_app/core/design_system/app_colors.dart';
import 'package:setu_app/core/design_system/app_radius.dart';
import 'package:setu_app/core/design_system/app_spacing.dart';
import 'package:setu_app/core/design_system/app_typography.dart';
import 'package:setu_app/core/design_system/widgets/design_system_widgets.dart';

import '../../data/models/nearby_alert_model.dart';
import '../../data/repositories/nearby_repository.dart';

class NearbyScreen extends StatefulWidget {
  const NearbyScreen({super.key});

  @override
  State<NearbyScreen> createState() => _NearbyScreenState();
}

class _NearbyScreenState extends State<NearbyScreen> {
  final NearbyRepository repository = NearbyRepository();
  List<NearbyAlertModel> alerts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    loadAlerts();
  }

  Future<void> loadAlerts() async {
    setState(() => _loading = true);
    alerts = await repository.getAlerts();
    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _openMap(double lat, double lng) async {
    final uri = Uri.parse("https://maps.google.com/?q=$lat,$lng");
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.bgApp : AppColors.lightBackground,
      appBar: AppBar(
        title: const Text("Nearby Mesh Broadcasts"),
        centerTitle: true,
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: loadAlerts,
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : alerts.isEmpty
                  ? const SetuEmptyState(
                      icon: Icons.cell_tower_rounded,
                      title: "No Nearby Distress Signals",
                      description:
                          "When nearby citizens broadcast public SOS alerts via Bluetooth or Wi-Fi mesh, they will be captured and displayed here in real time.",
                    )
                  : ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(
                        parent: BouncingScrollPhysics(),
                      ),
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      itemCount: alerts.length,
                      itemBuilder: (context, index) {
                        final alert = alerts[index];
                        final hasIncidentType = alert.incidentType.isNotEmpty;
                        final title = hasIncidentType
                            ? alert.incidentType.toUpperCase()
                            : "${alert.alertMode.name.toUpperCase()} SOS";

                        return Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                          child: SetuCard(
                            padding: const EdgeInsets.all(AppSpacing.md),
                            accentBorderLeft: AppColors.emergency,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppColors.emergency
                                            .withValues(alpha: 0.15),
                                        borderRadius: AppRadius.pillRadius,
                                        border: Border.all(
                                          color: AppColors.emergency
                                              .withValues(alpha: 0.4),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            Icons.warning_rounded,
                                            size: 12,
                                            color: AppColors.emergency,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            title,
                                            style: AppTypography.metadata.copyWith(
                                              color: AppColors.emergency,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Spacer(),
                                    Text(
                                      "MESH BROADCAST",
                                      style: AppTypography.metadata.copyWith(
                                        color: isDark
                                            ? AppColors.textDim
                                            : AppColors.lightTextDim,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ],
                                ),

                                const SizedBox(height: AppSpacing.sm),

                                Row(
                                  children: [
                                    Icon(
                                      Icons.location_on_outlined,
                                      size: 16,
                                      color: isDark
                                          ? AppColors.textDim
                                          : AppColors.lightTextDim,
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        "Coordinates: ${alert.latitude.toStringAsFixed(4)}, ${alert.longitude.toStringAsFixed(4)}",
                                        style: AppTypography.caption.copyWith(
                                          color: isDark
                                              ? AppColors.textSecondary
                                              : AppColors.lightTextSecondary,
                                        ),
                                      ),
                                    ),
                                    InkWell(
                                      onTap: () => _openMap(
                                        alert.latitude,
                                        alert.longitude,
                                      ),
                                      borderRadius: AppRadius.smRadius,
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              "View Location",
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
                              ],
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ),
    );
  }
}
