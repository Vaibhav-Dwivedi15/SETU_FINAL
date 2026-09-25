import 'package:flutter/material.dart';

/// What kind of citizen recovery report a record is.
///
/// Deliberately NOT a new PacketType / wire-format field: a report that is
/// dispatched travels as a normal signed EmergencyPacket (see
/// RecoveryPacketBuilder). [messagePrefix] is only a machine-parseable
/// tag at the start of the packet text; nothing in the backend consumes it
/// today.
enum RecoveryReportType {
  damage('Damage report', 'Damage', 'Report damaged buildings, roads or utilities',
      Icons.domain_disabled, '[RECOVERY:DAMAGE]'),
  missingPerson('Missing person', 'Missing person',
      'Report someone missing after a disaster', Icons.person_search,
      '[RECOVERY:MISSING_PERSON]'),
  resourceRequest('Help / resource request', 'Resource request',
      'Ask for food, water, medical help, shelter or rescue',
      Icons.volunteer_activism, '[RECOVERY:RESOURCE_REQUEST]');

  const RecoveryReportType(this.title, this.filterLabel, this.subtitle,
      this.icon, this.messagePrefix);

  final String title;

  /// Short label for filter chips.
  final String filterLabel;
  final String subtitle;
  final IconData icon;
  final String messagePrefix;
}
