// =====================================================
// SETU Project
// Module : Home Screen — Redesign Pass 1 (Block 30)
// Owner  : Sudheer
// =====================================================
//
// Following the Design System v1 delivered earlier. Business
// logic and routes are unchanged — every card still navigates
// to the exact same route as before. What changed is purely
// presentation: curved header (personalized greeting), a
// floating SOS card, and full-width descriptive service cards
// instead of small tiles that were truncating text.
//
// Aug 5 2026: connectivity status now comes from the shared
// ConnectivityMeshController.statusStream (single source of truth
// for the whole app) instead of a separate local Connectivity()
// instance -- so the home chip, the SOS flow, and everything else
// agree on one online/offline reading. Also: the offline state now
// shows a "Mesh Active" chip (green, hub icon) instead of a gray
// "Offline" chip -- per the product vision, no internet is exactly
// when SETU's mesh matters MOST, so the status should reassure
// ("your phone is now a relay node") rather than read as "dead".

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:setu_app/core/design_system/app_colors.dart';
import 'package:setu_app/core/design_system/app_elevation.dart';
import 'package:setu_app/core/design_system/app_radius.dart';
import 'package:setu_app/core/design_system/app_spacing.dart';
import 'package:setu_app/core/design_system/app_typography.dart';
import 'package:setu_app/core/design_system/widgets/status_chip.dart';
import 'package:setu_app/core/services/connectivity_mesh_controller.dart';
import 'package:setu_app/features/settings/data/repositories/settings_repository.dart';
import 'package:setu_app/features/sos/presentation/widgets/hold_to_confirm_sos_button.dart';
import 'package:setu_app/features/sos/presentation/widgets/tap_to_confirm_sos_button.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _ServiceItem {
  final IconData icon;
  final String title;
  final String description;
  final Color iconColor;
  final String route;

  const _ServiceItem({
    required this.icon,
    required this.title,
    required this.description,
    required this.iconColor,
    required this.route,
  });
}

class _HomeScreenState extends State<HomeScreen> {
  final SettingsRepository _settingsRepository = SettingsRepository();

  String _sosTriggerMode = 'tap';
  String _userName = '';

  // Aug 5 2026: now driven by the shared ConnectivityMeshController
  // instead of a local Connectivity() instance -- replaces the old
  // hardcoded "Offline" placeholder AND the earlier per-screen
  // connectivity listener.
  NetworkStatus _networkStatus = ConnectivityMeshController.instance.currentStatus;
  StreamSubscription<NetworkStatus>? _statusSubscription;

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
  }

  @override
  void dispose() {
    _statusSubscription?.cancel();
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

  static const _quickAccess = [
    _ServiceItem(
      icon: Icons.visibility_off,
      title: 'Stealth Mode',
      description: 'Disguised as a calculator for silent alerts',
      iconColor: AppColors.primary,
      route: '/stealth',
    ),
    _ServiceItem(
      icon: Icons.contacts,
      title: 'Emergency Contacts',
      description: 'People notified the moment you send SOS',
      iconColor: AppColors.primary,
      route: '/contacts',
    ),
  ];

  static const _safetyTools = [
    // PRIORITY 7 (BEFORE-disaster / preparedness): offline safety
    // guides + on-demand device readiness check. Placed first in
    // Safety Tools -- preparedness is what this section is for.
    _ServiceItem(
      icon: Icons.health_and_safety,
      title: 'Preparedness',
      description: 'Offline safety guides & device readiness check',
      iconColor: AppColors.info,
      route: '/preparedness',
    ),
    _ServiceItem(
      icon: Icons.history,
      title: 'SOS History',
      description: 'Past alerts, status, and locations sent',
      iconColor: AppColors.info,
      route: '/history',
    ),
    _ServiceItem(
      icon: Icons.wifi_tethering,
      title: 'Relay Status',
      description: 'Mesh network devices near you',
      iconColor: AppColors.info,
      route: '/relay',
    ),
    _ServiceItem(
      icon: Icons.people_alt,
      title: 'Nearby Alerts',
      description: 'Public SOS broadcasts around you',
      iconColor: AppColors.info,
      route: '/nearby',
    ),
  ];

  static const _community = [
    _ServiceItem(
      icon: Icons.volunteer_activism,
      title: 'Community (Demo)',
      description: 'Volunteer response & Humanity Score preview',
      iconColor: AppColors.success,
      route: '/community-demo',
    ),
    _ServiceItem(
      icon: Icons.child_care,
      title: 'Child Safety',
      description: 'Guardian, medical & safe-location profiles',
      iconColor: AppColors.success,
      route: '/child-safety',
    ),
    _ServiceItem(
      icon: Icons.campaign,
      title: 'Lost Child Alert (Demo)',
      description: 'Compose and preview a lost-child broadcast',
      iconColor: AppColors.success,
      route: '/lost-child',
    ),
  ];

  Widget _serviceCard(_ServiceItem item) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Material(
        color: Theme.of(context).cardColor,
        borderRadius: AppRadius.lgRadius,
        child: InkWell(
          borderRadius: AppRadius.lgRadius,
          onTap: () => context.push(item.route),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: AppRadius.lgRadius,
              boxShadow: Theme.of(context).brightness == Brightness.dark
                  ? null
                  : AppElevation.level1,
              border: Theme.of(context).brightness == Brightness.dark
                  ? Border.all(color: Theme.of(context).dividerColor)
                  : null,
            ),
            padding: const EdgeInsets.all(AppSpacing.sm + 4),
            child: Row(
              children: [
                Container(
                  height: 48,
                  width: 48,
                  decoration: BoxDecoration(
                    color: item.iconColor.withValues(alpha: 0.12),
                    borderRadius: AppRadius.mdRadius,
                  ),
                  child: Icon(item.icon, color: item.iconColor, size: 24),
                ),
                const SizedBox(width: AppSpacing.sm + 4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(item.title, style: AppTypography.subtitle),
                      const SizedBox(height: 2),
                      Text(
                        item.description,
                        style: AppTypography.caption.copyWith(
                          color: AppColors.neutral500,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: AppColors.neutral500,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, AppSpacing.lg, 0, AppSpacing.sm),
      child: Text(
        title,
        style: AppTypography.label.copyWith(color: AppColors.neutral500),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final greeting = _userName.isNotEmpty ? 'Hi, $_userName' : 'Welcome';
    final isOffline = _networkStatus == NetworkStatus.offline;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: CustomScrollView(
        slivers: [
          // ---------------- CURVED HEADER ----------------
          SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.xl,
                AppSpacing.lg,
                AppSpacing.xxl,
              ),
              decoration: const BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(AppRadius.xl),
                  bottomRight: Radius.circular(AppRadius.xl),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            greeting,
                            style: AppTypography.headline.copyWith(
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'SETU keeps help within reach',
                            style: AppTypography.body.copyWith(
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.settings, color: Colors.white),
                        onPressed: () => context.push('/settings'),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Wrap(
                    spacing: AppSpacing.xs,
                    children: [
                      // Aug 5 2026: offline now shows "Mesh Active" (green,
                      // reassuring) rather than a gray "Offline" chip -- no
                      // internet is precisely when SETU's mesh is doing its
                      // job, so the status should say so.
                      StatusChip(
                        kind: isOffline
                            ? StatusChipKind.meshActive
                            : StatusChipKind.connected,
                        labelOverride: isOffline ? 'Offline · Mesh Active' : null,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // ---------------- FLOATING SOS CARD ----------------
          SliverToBoxAdapter(
            child: Transform.translate(
              offset: const Offset(0, -32),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                ),
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: AppRadius.xlRadius,
                    boxShadow: AppElevation.level3,
                  ),
                  child: _sosTriggerMode == 'hold'
                      ? HoldToConfirmSosButton(onConfirmed: _onSosConfirmed)
                      : TapToConfirmSosButton(onConfirmed: _onSosConfirmed),
                ),
              ),
            ),
          ),

          // ---------------- CONTENT ----------------
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            sliver: SliverToBoxAdapter(
              child: Transform.translate(
                offset: const Offset(0, -20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionHeader('QUICK ACCESS'),
                    ..._quickAccess.map(_serviceCard),

                    _sectionHeader('SAFETY TOOLS'),
                    ..._safetyTools.map(_serviceCard),

                    _sectionHeader('FAMILY & COMMUNITY'),
                    ..._community.map(_serviceCard),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
