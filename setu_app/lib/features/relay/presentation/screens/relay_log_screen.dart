// =====================================================
// SETU Project
// Module : Relay Log Screen (persistent history)
// =====================================================
//
// Added Aug 6 2026. Mirrors history_screen.dart's exact structure --
// this is the persistent record that survives app restarts, unlike
// the live counters on RelayStatusScreen (which reset to 0 whenever
// the process restarts, since MeshMetrics is in-memory only). Reached
// via a button on RelayStatusScreen.

import 'package:flutter/material.dart';

import 'package:setu_app/core/design_system/app_colors.dart';
import 'package:setu_app/core/design_system/app_radius.dart';
import 'package:setu_app/core/design_system/app_spacing.dart';
import 'package:setu_app/core/design_system/app_typography.dart';
import 'package:setu_app/features/relay/data/models/relay_log_entry.dart';
import 'package:setu_app/features/relay/data/repositories/relay_log_repository.dart';

class RelayLogScreen extends StatefulWidget {
  const RelayLogScreen({super.key});

  @override
  State<RelayLogScreen> createState() => _RelayLogScreenState();
}

class _RelayLogScreenState extends State<RelayLogScreen> {
  List<RelayLogEntry> _log = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    _log = await RelayLogRepository.instance.getLog();
    if (!mounted) return;
    setState(() => _isLoading = false);
  }

  ({IconData icon, Color color, String label}) _spec(RelayLogType type) {
    switch (type) {
      case RelayLogType.sent:
        return (icon: Icons.send, color: AppColors.emergency, label: 'Sent');
      case RelayLogType.received:
        return (icon: Icons.call_received, color: AppColors.primary, label: 'Received');
      case RelayLogType.relayed:
        return (icon: Icons.sync, color: AppColors.relay, label: 'Relayed');
      case RelayLogType.uploaded:
        return (icon: Icons.cloud_upload, color: AppColors.success, label: 'Uploaded');
      case RelayLogType.dropped:
        return (icon: Icons.block, color: AppColors.neutral500, label: 'Dropped');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Relay History'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear history',
            onPressed: () async {
              await RelayLogRepository.instance.clearLog();
              await _load();
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _log.isEmpty
                ? ListView(
                    children: [
                      const SizedBox(height: 120),
                      Icon(Icons.history, size: 90, color: AppColors.neutral300),
                      const SizedBox(height: 20),
                      const Center(
                        child: Text(
                          'No Relay Activity Yet',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 40),
                          child: Text(
                            'Every packet your device sends, receives, or relays '
                            'will be logged here, permanently.',
                            textAlign: TextAlign.center,
                            style: AppTypography.caption.copyWith(color: AppColors.neutral500),
                          ),
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    itemCount: _log.length,
                    itemBuilder: (context, index) {
                      final entry = _log[index];
                      final spec = _spec(entry.type);
                      return Container(
                        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                        padding: const EdgeInsets.all(AppSpacing.md),
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardColor,
                          borderRadius: AppRadius.mdRadius,
                          border: Border.all(color: Theme.of(context).dividerColor),
                        ),
                        child: Row(
                          children: [
                            Container(
                              height: 40,
                              width: 40,
                              decoration: BoxDecoration(
                                color: spec.color.withValues(alpha: 0.12),
                                borderRadius: AppRadius.smRadius,
                              ),
                              child: Icon(spec.icon, color: spec.color, size: 20),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(spec.label, style: AppTypography.bodyStrong),
                                  if (entry.detail.isNotEmpty)
                                    Text(
                                      entry.detail,
                                      style: AppTypography.caption.copyWith(color: AppColors.neutral500),
                                    ),
                                ],
                              ),
                            ),
                            Text(
                              _formatTime(entry.timestamp),
                              style: AppTypography.caption.copyWith(color: AppColors.neutral500),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
      ),
    );
  }

  String _formatTime(DateTime t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
