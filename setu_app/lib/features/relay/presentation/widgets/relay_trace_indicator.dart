// =====================================================
// SETU Project
// Module : Relay Trace (mobile)
// =====================================================
//
// Added Aug 6 2026. Mirrors the dashboard's Relay Trace component
// (setu_dashboard/src/components/RelayTrace.jsx) -- same visual
// language (a chain of connected nodes) on both products.
//
// MeshMetrics only tracks an aggregate "relayed" counter for this
// device -- renders as a capped chain of up to 8 lit nodes (with a
// "+N more" label beyond that).

import 'package:flutter/material.dart';

import 'package:setu_app/core/design_system/app_colors.dart';

class RelayTraceIndicator extends StatelessWidget {
  final int relayedCount;

  const RelayTraceIndicator({super.key, required this.relayedCount});

  static const int _maxVisibleNodes = 8;

  @override
  Widget build(BuildContext context) {
    if (relayedCount == 0) {
      return Text(
        'No packets relayed yet',
        style: TextStyle(fontSize: 12, color: AppColors.neutral500),
      );
    }

    final visibleCount = relayedCount > _maxVisibleNodes ? _maxVisibleNodes : relayedCount;
    final overflow = relayedCount - visibleCount;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < visibleCount; i++) ...[
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: AppColors.relay,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: AppColors.relay.withValues(alpha: 0.4), blurRadius: 4),
              ],
            ),
          ),
          if (i < visibleCount - 1)
            Container(width: 8, height: 1.5, color: AppColors.relay.withValues(alpha: 0.5)),
        ],
        if (overflow > 0) ...[
          const SizedBox(width: 6),
          Text(
            '+$overflow more',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.relay,
            ),
          ),
        ],
      ],
    );
  }
}
