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

  bool _isSuccessStatus(String status) {
    // Only "Delivered" (see sos_repository.dart) counts as success.
    // Anything else — "Failed" or any future status string — must
    // NOT render as green. Showing a failed SOS as green in a
    // safety app is actively misleading.
    return status.toLowerCase() == 'delivered';
  }

  Widget _buildHistoryCard(HistoryModel item) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isSuccess = _isSuccessStatus(item.status);

    final chipBg = isSuccess
        ? (isDark
            ? Colors.green.shade900.withValues(alpha: 0.35)
            : Colors.green.shade100)
        : (isDark
            ? AppColors.primary.withValues(alpha: 0.3)
            : AppColors.primary.withValues(alpha: 0.12));

    final chipText = isSuccess
        ? (isDark ? Colors.greenAccent : Colors.green)
        : AppColors.primary;

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
                        isSuccess ? Icons.check_circle : Icons.error,
                        size: 14,
                        color: chipText,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        item.status,
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

            if (!isSuccess && item.errorReason.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline, color: AppColors.primary, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      item.errorReason,
                      style: const TextStyle(color: AppColors.primary, fontSize: 13),
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
