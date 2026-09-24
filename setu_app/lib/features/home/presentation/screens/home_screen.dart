// =====================================================
// SETU Project
// Module : Home Screen — Emergency-First Redesign
// =====================================================
//
// Designed to match SETU Operations Dashboard:
// - Deep charcoal / graphite surfaces (--bg-app: #080B12, --bg-surface: #111827)
// - Subtle high-contrast borders (--border-subtle: #3E526E)
// - Priority 1: Instant SOS action (prominent, accessible, no clutter)
// - Priority 2: Reassuring offline-first connectivity status
// - Priority 3: Quick emergency actions (Contacts, Stealth, Nearby, Relay)
// - Priority 4: Preparedness & Recovery entries
// - Priority 5: 4-tab bottom navigation (Home, Prepare, Recovery, History)
//
// All existing routes, background controllers, and business logic preserved.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:setu_app/core/design_system/app_colors.dart';
import 'package:setu_app/core/design_system/app_radius.dart';
import 'package:setu_app/core/design_system/app_spacing.dart';
import 'package:setu_app/core/design_system/app_typography.dart';
import 'package:setu_app/core/design_system/widgets/design_system_widgets.dart';
import 'package:setu_app/core/services/connectivity_mesh_controller.dart';
import 'package:setu_app/features/settings/data/repositories/settings_repository.dart';
import 'package:setu_app/mesh/services/mesh_metrics.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final SettingsRepository _settingsRepository = SettingsRepository();

  String _sosTriggerMode = 'tap';
  String _userName = '';

  NetworkStatus _networkStatus =
      ConnectivityMeshController.instance.currentStatus;
  StreamSubscription<NetworkStatus>? _statusSubscription;
  StreamSubscription<void>? _metricsSubscription;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _initConnectivity();
  }

  void _initConnectivity() {
    _statusSubscription =
        ConnectivityMeshController.instance.statusStream.listen((status) {
      if (!mounted) return;
      setState(() => _networkStatus = status);
    });

    _metricsSubscription = MeshMetrics.instance.changes.listen((_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _statusSubscription?.cancel();
    _metricsSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final settings = await _settingsRepository.getSettings();
    if (!mounted) return;
    setState(() {
      _sosTriggerMode = settings.sosTriggerMode;
      _userName = settings.userName;
    });
  }

  void _onSosConfirmed() => context.push('/confirmation');

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isOffline = _networkStatus == NetworkStatus.offline;

    final triggerStyle = _sosTriggerMode == 'hold'
        ? SetuEmergencyTriggerStyle.hold
        : SetuEmergencyTriggerStyle.tap;

    return Scaffold(
      backgroundColor: isDark ? AppColors.bgApp : AppColors.lightBackground,
      bottomNavigationBar: SetuBottomNavigation(
        currentIndex: 0,
        onTap: (index) {
          switch (index) {
            case 0:
              // Already on Home
              break;
            case 1:
              context.push('/preparedness');
              break;
            case 2:
              context.push('/recovery');
              break;
            case 3:
              context.push('/history');
              break;
          }
        },
      ),
      body: SafeArea(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // ---------------- 1. APP HEADER ----------------
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.md,
                  AppSpacing.lg,
                  AppSpacing.sm,
                ),
                child: Row(
                  children: [
                    // Brand / Logo mark
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.emergency.withValues(alpha: 0.14),
                        borderRadius: AppRadius.smRadius,
                        border: Border.all(
                          color: AppColors.emergency.withValues(alpha: 0.3),
                          width: 1,
                        ),
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.emergency_rounded,
                          color: AppColors.emergency,
                          size: 20,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SETU',
                          style: AppTypography.title.copyWith(
                            letterSpacing: 1.0,
                            fontWeight: FontWeight.w800,
                            color: isDark
                                ? AppColors.textPrimary
                                : AppColors.lightTextPrimary,
                          ),
                        ),
                        Text(
                          _userName.isNotEmpty
                              ? 'Citizen: $_userName'
                              : 'Emergency Response System',
                          style: AppTypography.metadata.copyWith(
                            color: isDark
                                ? AppColors.textDim
                                : AppColors.lightTextDim,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    // Connectivity Pill
                    SetuStatusIndicator(
                      status: isOffline
                          ? SetuStatusType.meshActive
                          : SetuStatusType.online,
                      showDot: true,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    // Settings button
                    IconButton(
                      icon: Icon(
                        Icons.settings_outlined,
                        color: isDark
                            ? AppColors.textSecondary
                            : AppColors.lightTextSecondary,
                        size: 22,
                      ),
                      tooltip: 'Settings',
                      onPressed: () => context.push('/settings'),
                    ),
                  ],
                ),
              ),
            ),

            // ---------------- 2. HERO SOS SECTION ----------------
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.sm,
                ),
                child: SetuCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.lg,
                  ),
                  backgroundColor: isDark
                      ? AppColors.bgSurface
                      : AppColors.lightSurface,
                  borderColor: isDark
                      ? AppColors.borderSubtle
                      : AppColors.lightBorder,
                  child: Column(
                    children: [
                      Text(
                        'DISTRESS BEACON',
                        style: AppTypography.metadata.copyWith(
                          color: AppColors.emergency,
                          letterSpacing: 1.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'Tap or hold to broadcast emergency alert',
                        textAlign: TextAlign.center,
                        style: AppTypography.supporting.copyWith(
                          color: isDark
                              ? AppColors.textSecondary
                              : AppColors.lightTextSecondary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      SetuEmergencyButton(
                        onTriggered: _onSosConfirmed,
                        triggerStyle: triggerStyle,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? AppColors.bgInput
                              : AppColors.lightBackground,
                          borderRadius: AppRadius.pillRadius,
                          border: Border.all(
                            color: isDark
                                ? AppColors.borderSubtle
                                : AppColors.lightBorder,
                            width: 0.8,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.security_rounded,
                              size: 14,
                              color: isDark
                                  ? AppColors.textDim
                                  : AppColors.lightTextDim,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'GPS coordinates & digital signature attached',
                              style: AppTypography.metadata.copyWith(
                                color: isDark
                                    ? AppColors.textDim
                                    : AppColors.lightTextDim,
                                fontSize: 10.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ---------------- 3. REASSURING OFFLINE / NETWORK BANNER ----------------
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: SetuOfflineBanner(
                  isOffline: isOffline,
                  peerCount: MeshMetrics.instance.received > 0
                      ? MeshMetrics.instance.received
                      : null,
                  onTap: () => context.push('/relay'),
                ),
              ),
            ),

            // ---------------- 4. QUICK EMERGENCY ACTIONS ----------------
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.sm,
                  AppSpacing.lg,
                  0,
                ),
                child: const SetuSectionHeader(
                  title: 'Quick Actions',
                  subtitle: 'Immediate safety & communication controls',
                ),
              ),
            ),

            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: AppSpacing.sm,
                  crossAxisSpacing: AppSpacing.sm,
                  childAspectRatio: 2.2,
                ),
                delegate: SliverChildListDelegate([
                  _buildQuickActionTile(
                    context: context,
                    icon: Icons.contacts_rounded,
                    title: 'Contacts',
                    subtitle: 'Emergency list',
                    route: '/contacts',
                    accentColor: AppColors.accent,
                  ),
                  _buildQuickActionTile(
                    context: context,
                    icon: Icons.visibility_off_rounded,
                    title: 'Stealth SOS',
                    subtitle: 'Calculator disguise',
                    route: '/stealth',
                    accentColor: AppColors.warning,
                  ),
                  _buildQuickActionTile(
                    context: context,
                    icon: Icons.hub_rounded,
                    title: 'Mesh Relay',
                    subtitle: 'Nearby nodes',
                    route: '/relay',
                    accentColor: AppColors.relay,
                  ),
                  _buildQuickActionTile(
                    context: context,
                    icon: Icons.people_alt_rounded,
                    title: 'Nearby Alerts',
                    subtitle: 'Local broadcasts',
                    route: '/nearby',
                    accentColor: AppColors.accent,
                  ),
                ]),
              ),
            ),

            // ---------------- 5. BEFORE & AFTER DISASTER (PREPAREDNESS & RECOVERY) ----------------
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.md,
                  AppSpacing.lg,
                  AppSpacing.xs,
                ),
                child: const SetuSectionHeader(
                  title: 'Disaster Hubs',
                  subtitle: 'Preparation and post-emergency response',
                ),
              ),
            ),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: Column(
                  children: [
                    SetuCard(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      onTap: () => context.push('/preparedness'),
                      accentBorderLeft: AppColors.accent,
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: AppColors.accent.withValues(alpha: 0.12),
                              borderRadius: AppRadius.smRadius,
                            ),
                            child: const Icon(
                              Icons.health_and_safety_rounded,
                              color: AppColors.accent,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      'Preparedness Hub',
                                      style: AppTypography.cardTitle.copyWith(
                                        color: isDark
                                            ? AppColors.textPrimary
                                            : AppColors.lightTextPrimary,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 1.5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppColors.success
                                            .withValues(alpha: 0.15),
                                        borderRadius: AppRadius.pillRadius,
                                      ),
                                      child: Text(
                                        'OFFLINE',
                                        style: AppTypography.metadata.copyWith(
                                          color: AppColors.success,
                                          fontSize: 9.5,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Offline safety guides & device readiness check',
                                  style: AppTypography.caption.copyWith(
                                    color: isDark
                                        ? AppColors.textSecondary
                                        : AppColors.lightTextSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: isDark
                                ? AppColors.textDim
                                : AppColors.lightTextDim,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    SetuCard(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      onTap: () => context.push('/recovery'),
                      accentBorderLeft: AppColors.warning,
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: AppColors.warning.withValues(alpha: 0.12),
                              borderRadius: AppRadius.smRadius,
                            ),
                            child: const Icon(
                              Icons.restore_rounded,
                              color: AppColors.warning,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Recovery & Incident Reporting',
                                  style: AppTypography.cardTitle.copyWith(
                                    color: isDark
                                        ? AppColors.textPrimary
                                        : AppColors.lightTextPrimary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Report damage, missing persons, resources & status',
                                  style: AppTypography.caption.copyWith(
                                    color: isDark
                                        ? AppColors.textSecondary
                                        : AppColors.lightTextSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: isDark
                                ? AppColors.textDim
                                : AppColors.lightTextDim,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ---------------- 6. COMMUNITY & SPECIAL TOOLS ----------------
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.md,
                  AppSpacing.lg,
                  AppSpacing.xs,
                ),
                child: const SetuSectionHeader(
                  title: 'Community & Family Safety',
                  subtitle: 'Guardianship & volunteer response',
                ),
              ),
            ),

            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.xl,
              ),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  _buildSecondaryRow(
                    context: context,
                    icon: Icons.child_care_rounded,
                    title: 'Child Safety Profiles',
                    subtitle: 'Guardian contacts, medical details & safe zones',
                    route: '/child-safety',
                  ),
                  _buildSecondaryRow(
                    context: context,
                    icon: Icons.campaign_rounded,
                    title: 'Lost Child Broadcast (Demo)',
                    subtitle: 'Compose rapid mesh alerts for missing children',
                    route: '/lost-child',
                  ),
                  _buildSecondaryRow(
                    context: context,
                    icon: Icons.mic_rounded,
                    title: 'Voice Emergency SOS',
                    subtitle: 'Record voice distress note for online intake',
                    route: '/voice-sos',
                  ),
                  _buildSecondaryRow(
                    context: context,
                    icon: Icons.volunteer_activism_rounded,
                    title: 'Community Response (Demo)',
                    subtitle: 'Volunteer network & Humanity Score',
                    route: '/community-demo',
                  ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActionTile({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required String route,
    required Color accentColor,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SetuCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      onTap: () => context.push(route),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.12),
              borderRadius: AppRadius.smRadius,
            ),
            child: Icon(icon, color: accentColor, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: AppTypography.cardTitle.copyWith(
                    fontSize: 13.5,
                    color: isDark
                        ? AppColors.textPrimary
                        : AppColors.lightTextPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  subtitle,
                  style: AppTypography.caption.copyWith(
                    fontSize: 11,
                    color: isDark
                        ? AppColors.textDim
                        : AppColors.lightTextDim,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSecondaryRow({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required String route,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: SetuCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        onTap: () => context.push(route),
        child: Row(
          children: [
            Icon(
              icon,
              size: 22,
              color: isDark ? AppColors.textSecondary : AppColors.lightTextSecondary,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTypography.bodyStrong.copyWith(
                      color: isDark
                          ? AppColors.textPrimary
                          : AppColors.lightTextPrimary,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    style: AppTypography.caption.copyWith(
                      color: isDark
                          ? AppColors.textDim
                          : AppColors.lightTextDim,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: isDark ? AppColors.textDim : AppColors.lightTextDim,
            ),
          ],
        ),
      ),
    );
  }
}
