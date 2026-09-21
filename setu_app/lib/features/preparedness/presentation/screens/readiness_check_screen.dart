import 'package:flutter/material.dart';

import '../../data/models/readiness_status.dart';
import '../../data/repositories/readiness_repository.dart';

/// On-demand "Am I ready?" check.
///
/// Distinct from permission_gate_screen.dart (onboarding, runs once,
/// blocks progress until granted): this is re-checkable any time from
/// the Preparedness tab, because Bluetooth/location get turned off by
/// users constantly and a device that silently stopped being a usable
/// relay is exactly the kind of gap preparedness should catch ahead of
/// an emergency.
class ReadinessCheckScreen extends StatefulWidget {
  const ReadinessCheckScreen({super.key});

  @override
  State<ReadinessCheckScreen> createState() => _ReadinessCheckScreenState();
}

class _ReadinessCheckScreenState extends State<ReadinessCheckScreen> {
  final ReadinessRepository _repository = const ReadinessRepository();
  ReadinessStatus? _status;
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _runCheck();
  }

  Future<void> _runCheck() async {
    setState(() => _checking = true);
    final status = await _repository.check();
    if (!mounted) return;
    setState(() {
      _status = status;
      _checking = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Device readiness'),
        actions: [
          IconButton(
            onPressed: _checking ? null : _runCheck,
            icon: const Icon(Icons.refresh),
            tooltip: 'Re-check',
          ),
        ],
      ),
      body: _checking || status == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _runCheck,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _OverallBanner(ready: status.ready),
                  const SizedBox(height: 16),
                  _CheckRow(
                    label: 'Permissions',
                    ok: status.permissionsGranted,
                    detail: status.permissionsGranted
                        ? 'Bluetooth and location granted'
                        : 'Missing — open Settings to grant',
                  ),
                  _CheckRow(
                    label: 'Bluetooth',
                    ok: status.bluetoothEnabled,
                    detail: status.bluetoothEnabled ? 'On' : 'Off — turn on to relay nearby',
                  ),
                  _CheckRow(
                    label: 'Wi-Fi',
                    ok: status.wifiEnabled,
                    detail: status.wifiEnabled ? 'On' : 'Off — some mesh links use Wi-Fi Direct',
                  ),
                  _CheckRow(
                    label: 'Mesh peers nearby',
                    ok: true,
                    neutral: true,
                    detail: status.connectedPeers == 0
                        ? 'None connected right now — normal if nobody is nearby'
                        : '${status.connectedPeers} device(s) connected',
                  ),
                  _CheckRow(
                    label: 'Battery',
                    ok: status.batteryLevel > 20 || status.batteryLevel == 0,
                    detail: status.batteryLevel > 0
                        ? '${status.batteryLevel}%'
                        : 'Unavailable on this build',
                  ),
                  if (status.problems.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text('What to fix', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 8),
                    for (final problem in status.problems)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text('• $problem'),
                      ),
                  ],
                ],
              ),
            ),
    );
  }
}

class _OverallBanner extends StatelessWidget {
  const _OverallBanner({required this.ready});
  final bool ready;

  @override
  Widget build(BuildContext context) {
    final color = ready ? Colors.green : Colors.orange;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(ready ? Icons.check_circle : Icons.warning_amber, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              ready
                  ? "This device is ready to relay emergency traffic."
                  : "This device isn't fully ready — see below.",
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({
    required this.label,
    required this.ok,
    required this.detail,
    this.neutral = false,
  });

  final String label;
  final bool ok;
  final String detail;

  /// True for informational rows (e.g. peer count) that should never
  /// render as a red "failed" state.
  final bool neutral;

  @override
  Widget build(BuildContext context) {
    final icon = neutral
        ? Icons.info_outline
        : (ok ? Icons.check_circle_outline : Icons.error_outline);
    final color = neutral ? Colors.blueGrey : (ok ? Colors.green : Colors.red);
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(label),
      subtitle: Text(detail),
      dense: true,
    );
  }
}
