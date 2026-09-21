import 'package:flutter/material.dart';

import '../../data/models/recovery_report_type.dart';
import '../../data/repositories/recovery_repository.dart';

/// One generic form for every RecoveryReportType -- the type only
/// changes the title, hint text, and message prefix (see
/// RecoveryReportType.messagePrefix); the underlying send path
/// (RecoveryRepository.submitReport) is identical. Minimal UI on
/// purpose, matching PreparednessScreen/ReadinessCheckScreen's own
/// stated bar: functional engineering over cosmetics for this sprint.
class RecoveryReportFormScreen extends StatefulWidget {
  const RecoveryReportFormScreen({super.key, required this.type});

  final RecoveryReportType type;

  @override
  State<RecoveryReportFormScreen> createState() => _RecoveryReportFormScreenState();
}

class _RecoveryReportFormScreenState extends State<RecoveryReportFormScreen> {
  final _repository = RecoveryRepository();
  final _controller = TextEditingController();
  bool _sending = false;
  String? _error;

  // Matches the backend's PacketIn.message bound (Field(max_length=2000)
  // in schemas/packet.py, added the same sprint) so the form can't build
  // a report the backend would reject anyway -- kept well under that
  // limit for a comfortable on-screen counter, not to exactly mirror it.
  static const int _maxMessageLength = 500;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final message = _controller.text.trim();
    if (message.isEmpty) {
      setState(() => _error = 'Please enter a message before sending.');
      return;
    }

    setState(() {
      _sending = true;
      _error = null;
    });

    try {
      await _repository.submitReport(type: widget.type, message: message);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${widget.type.title} sent over the mesh.')),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final type = widget.type;
    return Scaffold(
      appBar: AppBar(title: Text(type.title)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(type.icon, size: 32),
                const SizedBox(width: 12),
                Expanded(child: Text(type.subtitle)),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              maxLength: _maxMessageLength,
              maxLines: 5,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Details',
                hintText: 'Describe what you want to report...',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 16),
            const Text(
              'This is sent over the mesh -- no internet needed. It will '
              'sync to the responder dashboard automatically once any '
              'device in the relay chain regains connectivity.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _sending ? null : _submit,
              icon: _sending
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
              label: Text(_sending ? 'Sending...' : 'Send report'),
            ),
          ],
        ),
      ),
    );
  }
}
