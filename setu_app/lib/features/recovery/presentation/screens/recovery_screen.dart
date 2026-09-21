import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/recovery_report_model.dart';
import '../../data/models/recovery_report_type.dart';
import '../../data/repositories/recovery_repository.dart';

/// AFTER-disaster hub: send a recovery-phase report (damage,
/// missing-person, resource, status, community update) and see this
/// device's own recently-sent reports. Priority 8 of the session brief
/// -- the counterpart to PreparednessScreen's BEFORE-disaster hub.
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
    return Scaffold(
      appBar: AppBar(title: const Text('Recovery')),
      body: RefreshIndicator(
        onRefresh: () async => _reload(),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Report after the emergency',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            ...RecoveryReportType.values.map(
              (type) => Card(
                child: ListTile(
                  leading: Icon(type.icon),
                  title: Text(type.title),
                  subtitle: Text(type.subtitle),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _openForm(type),
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Your recent reports',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            FutureBuilder<List<RecoveryReportModel>>(
              future: _reports,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final reports = snapshot.data ?? const [];
                if (reports.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      "You haven't sent any recovery reports yet.",
                      style: TextStyle(color: Colors.grey),
                    ),
                  );
                }
                return Column(
                  children: reports
                      .map(
                        (report) => ListTile(
                          leading: Icon(report.type.icon),
                          title: Text(report.type.title),
                          subtitle: Text(
                            report.message,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Text(
                            _formatTimestamp(report.timestamp),
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ),
                      )
                      .toList(),
                );
              },
            ),
          ],
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
