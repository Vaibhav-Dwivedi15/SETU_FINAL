import 'package:flutter/material.dart';

/// Honest local lifecycle of a recovery report. Nothing here claims an
/// authority has seen a report.
enum ReportStatus {
  /// Being written; not sent anywhere.
  draft('Draft', 'Draft. Not sent yet.', Icons.edit_note_rounded),

  /// Saved on this device and handed to the mesh store-and-forward queue
  /// (or waiting to be). No acknowledgement received yet.
  pendingSync(
      'Pending sync',
      'Saved on this device. Will sync when connectivity is available.',
      Icons.schedule_rounded),

  /// A SETU node acknowledged receipt of the packet. This is a network
  /// acknowledgement, NOT confirmation that any authority has reviewed it.
  submitted(
      'Submitted',
      'A SETU node acknowledged receipt. This does not confirm that '
          'authorities have reviewed it.',
      Icons.check_circle_outline_rounded),

  /// The send attempt failed. The report is still saved locally and can
  /// be retried.
  failed('Failed', 'Sync failed. Report remains saved locally.',
      Icons.error_outline_rounded);

  const ReportStatus(this.label, this.description, this.icon);

  final String label;
  final String description;
  final IconData icon;

  /// Draft and failed reports can still be edited; a report that has been
  /// dispatched (pending/submitted) must not change under the packet that
  /// already carries its content.
  bool get isEditable => this == draft || this == failed;
  bool get canRetry => this == failed;
}
