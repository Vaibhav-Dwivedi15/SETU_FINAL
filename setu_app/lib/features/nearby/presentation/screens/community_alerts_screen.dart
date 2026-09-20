// =====================================================
// SETU Project
// Module : Community Alerts (backend-driven, Phase 3)
// Owner  : Sudheer
// =====================================================
//
// DIFFERENT FROM /nearby (NearbyScreen): that screen shows LOCAL mesh
// AlertPackets received directly over BLE/Wi-Fi Direct from other
// devices. THIS screen polls the backend's GET /alerts/nearby with this
// device's current location and lets the user record a response action
// (I'm nearby / I can help / etc.) via POST /alerts/{id}/respond. Two
// genuinely different data sources — see backend_alerts_service.dart's
// module docstring for the full reasoning. Both screens are kept, not
// merged, so each stays honest about what it actually shows.
//
// POLLING, NOT PUSH: this screen fetches once on open and again every
// POLL_INTERVAL while visible. It does NOT receive a push notification
// the instant a new incident appears elsewhere — see the backend's own
// nearby_alert_service.py on why (no FCM infrastructure exists). A user
// only sees a new alert here if they have this screen open, or the app
// running and this screen gets revisited.
//
// REQUIRES INTERNET: like voice SOS, this cannot work over the offline
// mesh — it's a direct backend call. If there's no connectivity,
// fetchNearby() returns an empty list (see service docstring) and this
// screen shows its own empty state rather than erroring.

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:setu_app/core/design_system/app_colors.dart';
import 'package:setu_app/core/design_system/app_radius.dart';
import 'package:setu_app/core/design_system/app_spacing.dart';
import 'package:setu_app/core/design_system/app_typography.dart';
import 'package:setu_app/core/language/app_strings.dart';
import 'package:setu_app/features/location/data/services/location_service.dart';
import 'package:setu_app/mesh/services/signing_service.dart';
import 'package:setu_app/services/backend_alerts_service.dart';

const _pollInterval = Duration(seconds: 30);

class CommunityAlertsScreen extends StatefulWidget {
  const CommunityAlertsScreen({super.key});

  @override
  State<CommunityAlertsScreen> createState() => _CommunityAlertsScreenState();
}

class _CommunityAlertsScreenState extends State<CommunityAlertsScreen> {
  final BackendAlertsService _alertsService = BackendAlertsService();
  final LocationService _locationService = LocationService();
  final SigningService _signingService = SigningService();

  List<BackendNearbyAlert> _alerts = [];
  bool _loading = true;
  String? _error;
  Timer? _pollTimer;
  String? _senderId;

  // Tracks which incidentIds this device has already responded to THIS
  // session, so the UI can show a confirmed state immediately without
  // waiting for the next poll (the backend also excludes these from
  // future fetchNearby() calls once senderId is passed, but that only
  // takes effect on the NEXT poll — this local set closes that gap).
  final Set<int> _respondedIds = {};

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    _senderId = await _signingService.getOrCreatePublicKeyHex();
    await _fetch();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _fetch());
  }

  Future<void> _fetch() async {
    double latitude = 0.0;
    double longitude = 0.0;
    try {
      final location = await _locationService.getCurrentLocation();
      latitude = location.latitude;
      longitude = location.longitude;
    } catch (e) {
      if (mounted && _alerts.isEmpty) {
        setState(() {
          _loading = false;
          _error = 'Could not get your location. Enable location services to see nearby alerts.';
        });
      }
      return;
    }

    final results = await _alertsService.fetchNearby(
      latitude: latitude,
      longitude: longitude,
      senderId: _senderId,
    );

    if (!mounted) return;
    setState(() {
      _alerts = results;
      _loading = false;
      _error = null;
    });
  }

  Future<void> _respond(BackendNearbyAlert alert, CommunityResponseType type) async {
    if (_senderId == null) return;

    final ok = await _alertsService.respond(
      incidentId: alert.incidentId,
      senderId: _senderId!,
      responseType: type,
    );

    if (!mounted) return;

    if (ok) {
      setState(() => _respondedIds.add(alert.incidentId));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Response recorded. Thank you for helping.')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not send your response. Check your connection.')),
      );
    }
  }

  void _showResponseSheet(BackendNearbyAlert alert) {
    final strings = AppStrings.of(context);
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: AppSpacing.sm),
            Text('How can you help?', style: AppTypography.subtitle),
            const SizedBox(height: AppSpacing.sm),
            _responseTile(
              sheetContext,
              alert,
              strings.t('nearby.respondNearby'),
              Icons.person_pin_circle_outlined,
              CommunityResponseType.nearby,
            ),
            _responseTile(
              sheetContext,
              alert,
              strings.t('nearby.respondCanHelp'),
              Icons.volunteer_activism_outlined,
              CommunityResponseType.canHelp,
            ),
            _responseTile(
              sheetContext,
              alert,
              strings.t('nearby.respondAlreadyResponding'),
              Icons.directions_run,
              CommunityResponseType.alreadyResponding,
            ),
            _responseTile(
              sheetContext,
              alert,
              strings.t('nearby.respondCalledServices'),
              Icons.call,
              CommunityResponseType.calledEmergencyServices,
            ),
            _responseTile(
              sheetContext,
              alert,
              strings.t('nearby.respondNavigating'),
              Icons.navigation_outlined,
              CommunityResponseType.navigating,
            ),
            const SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
    );
  }

  Widget _responseTile(
    BuildContext sheetContext,
    BackendNearbyAlert alert,
    String label,
    IconData icon,
    CommunityResponseType type,
  ) {
    return ListTile(
      leading: Icon(icon, color: AppColors.primary),
      title: Text(label),
      onTap: () {
        Navigator.of(sheetContext).pop();
        _respond(alert, type);
      },
    );
  }

  String _formatDistance(double km) {
    if (km < 1) return '${(km * 1000).round()} m away';
    return '${km.toStringAsFixed(1)} km away';
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(strings.t('nearby.title'))),
      body: RefreshIndicator(
        onRefresh: _fetch,
        child: _buildBody(strings),
      ),
    );
  }

  Widget _buildBody(AppStrings strings) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return ListView(
        children: [
          const SizedBox(height: 100),
          Icon(Icons.location_off_outlined, size: 72, color: AppColors.neutral500),
          const SizedBox(height: AppSpacing.md),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Text(
              _error!,
              textAlign: TextAlign.center,
              style: AppTypography.body.copyWith(color: AppColors.neutral500),
            ),
          ),
        ],
      );
    }

    if (_alerts.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 100),
          const Icon(Icons.people_alt_outlined, size: 90, color: Colors.grey),
          const SizedBox(height: AppSpacing.md),
          Center(
            child: Text(strings.t('nearby.empty'), style: AppTypography.subtitle),
          ),
          const SizedBox(height: AppSpacing.sm),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'Emergencies reported near your current location will appear here.',
              textAlign: TextAlign.center,
              style: AppTypography.caption.copyWith(color: AppColors.neutral500),
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(AppSpacing.md),
      itemCount: _alerts.length,
      itemBuilder: (context, index) {
        final alert = _alerts[index];
        final responded = _respondedIds.contains(alert.incidentId);

        return Card(
          margin: const EdgeInsets.only(bottom: AppSpacing.sm),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.lgRadius),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      height: 44,
                      width: 44,
                      decoration: const BoxDecoration(
                        color: AppColors.emergency,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.warning_amber_rounded, color: Colors.white),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            alert.incidentType.toUpperCase(),
                            style: AppTypography.subtitle.copyWith(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            _formatDistance(alert.distanceKm),
                            style: AppTypography.caption.copyWith(color: AppColors.neutral500),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(alert.message, style: AppTypography.body),
                const SizedBox(height: AppSpacing.sm),
                SizedBox(
                  width: double.infinity,
                  child: responded
                      ? OutlinedButton.icon(
                          onPressed: null,
                          icon: const Icon(Icons.check),
                          label: const Text('Response recorded'),
                        )
                      : FilledButton(
                          onPressed: () => _showResponseSheet(alert),
                          child: const Text('Respond'),
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
