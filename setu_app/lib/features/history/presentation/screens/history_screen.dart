import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:setu_app/core/constants/app_colors.dart';

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
        const SnackBar(content: Text("Unable to open Google Maps")),
      );
    }
  }

  Future<void> _refresh() async {
    await _loadHistory();
  }

  @override
  Widget build(BuildContext context) {
    // Scaffold/AppBar colors come from Theme (light/dark) —
    // no more hardcoded white AppBar / light background.
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text(
          "Emergency History",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),

      body: RefreshIndicator(
        // Aug 5 2026: pull-to-refresh is how a real ack update (see
        // MeshLocator's acknowledgments listener + HistoryService.
        // updateStatusByEmergencyId) becomes visible on this screen if
        // it arrives while this screen is already open. There's no
        // live stream subscription here -- that's a deliberate,
        // honestly-scoped choice: a real-time listener on this screen
        // would need careful lifecycle handling (subscribe/unsubscribe
        // on screen enter/exit) that's a bigger change than this pass
        // covers. Pull-to-refresh is a correct, if not instant, way to
        // see the update.
        onRefresh: _refresh,

        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _history.isEmpty
            ? _buildEmptyState()
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _history.length,
                itemBuilder: (context, index) {
                  final item = _history[index];

                  return _buildHistoryCard(item);
                },
              ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return ListView(
      children: const [
        SizedBox(height: 120),

        Icon(Icons.history, size: 90, color: Colors.grey),

        SizedBox(height: 20),

        Center(
          child: Text(
            "No Emergency History",
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
        ),

        SizedBox(height: 12),

        Center(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              "Every emergency event will automatically appear here.",
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    );
  }

  // Aug 5 2026: previously binary (isSuccess / not-success), and
  // "not-success" rendered in AppColors.primary (blue) regardless of
  // whether the status was "Failed" or anything else -- meaning an
  // actual failed SOS never actually showed red, contradicting this
  // file's own comment about honesty. Now three real states:
  //   - "Delivered": genuinely confirmed (real ack, or awaited
  //     backend confirmation for the online path) -- green.
  //   - "Sent": handed off to mesh/SMS, awaiting real confirmation --
  //     neutral/blue, hourglass icon. This is the honest default for
  //     the offline/mesh path now, replacing the old immediate
  //     "Delivered" claim (see sos_repository.dart).
  //   - Anything else (i.e. "Failed"): genuine failure -- red.
  bool _isDeliveredStatus(String status) => status.toLowerCase() == 'delivered';
  bool _isSentStatus(String status) => status.toLowerCase() == 'sent';

  Widget _buildHistoryCard(HistoryModel item) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isDelivered = _isDeliveredStatus(item.status);
    final isSent = _isSentStatus(item.status);
    final isFailed = !isDelivered && !isSent;

    final Color chipBg;
    final Color chipText;
    final IconData chipIcon;

    if (isDelivered) {
      chipBg = isDark ? Colors.green.shade900.withValues(alpha: 0.35) : Colors.green.shade100;
      chipText = isDark ? Colors.greenAccent : Colors.green;
      chipIcon = Icons.check_circle;
    } else if (isSent) {
      chipBg = isDark
          ? AppColors.primary.withValues(alpha: 0.3)
          : AppColors.primary.withValues(alpha: 0.12);
      chipText = AppColors.primary;
      chipIcon = Icons.hourglass_top_rounded;
    } else {
      // Genuine failure -- now actually red, not blue.
      chipBg = isDark
          ? AppColors.danger.withValues(alpha: 0.3)
          : AppColors.danger.withValues(alpha: 0.12);
      chipText = AppColors.danger;
      chipIcon = Icons.error;
    }

    return Card(
      elevation: 4,
      margin: const EdgeInsets.only(bottom: 16),

      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),

      child: Padding(
        padding: const EdgeInsets.all(18),

        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,

          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),

                  decoration: BoxDecoration(
                    color: chipBg,
                    borderRadius: BorderRadius.circular(30),
                  ),

                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        chipIcon,
                        size: 14,
                        color: chipText,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isSent ? '${item.status} · awaiting confirmation' : item.status,
                        style: TextStyle(
                          color: chipText,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),

                const Spacer(),

                Text(
                  item.timestamp.toString(),
                  style: const TextStyle(color: Colors.grey),
                ),
              ],
            ),

            const SizedBox(height: 18),

            Row(
              children: [
                const Icon(Icons.people),

                const SizedBox(width: 10),

                Text("${item.recipients.length} Contacts"),
              ],
            ),

            const SizedBox(height: 12),

            Row(
              children: [
                const Icon(Icons.location_on),

                const SizedBox(width: 10),

                Expanded(child: Text("${item.latitude}, ${item.longitude}")),
              ],
            ),

            if (isFailed && item.errorReason.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline, color: AppColors.danger, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      item.errorReason,
                      style: const TextStyle(color: AppColors.danger, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,

              child: FilledButton.icon(
                onPressed: () {
                  _openGoogleMaps(item.mapsLink);
                },

                icon: const Icon(Icons.map),

                label: const Text("Open Google Maps"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
