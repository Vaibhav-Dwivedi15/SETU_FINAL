import 'package:flutter/material.dart';

/// The phase of a disaster a group of guide actions belongs to.
/// [steps] is the fallback for flat, non-phased guides (e.g. women's
/// safety), which have one ordered list and no phases.
enum GuideSectionKind {
  before('before', 'Before', Icons.event_available_rounded),
  during('during', 'During', Icons.warning_amber_rounded),
  after('after', 'After', Icons.healing_rounded),
  avoid('avoid', 'Avoid', Icons.block_rounded),
  steps('steps', 'Action steps', Icons.format_list_numbered_rounded);

  const GuideSectionKind(this.key, this.title, this.icon);

  final String key;
  final String title;
  final IconData icon;

  static GuideSectionKind? fromKey(String key) {
    for (final kind in GuideSectionKind.values) {
      if (kind.key == key) return kind;
    }
    return null;
  }
}

class GuideSection {
  const GuideSection({required this.kind, required this.items});

  final GuideSectionKind kind;
  final List<String> items;
}
