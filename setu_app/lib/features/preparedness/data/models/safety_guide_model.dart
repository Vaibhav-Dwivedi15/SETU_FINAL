import 'disaster_type.dart';
import 'guide_section.dart';

/// One bundled, offline safety guide.
///
/// Accepts two JSON shapes so existing flat guides keep working:
///  * phased:  `"sections": {"before": [...], "during": [...], ...}`
///  * flat:    `"steps": [...]` (becomes a single [GuideSectionKind.steps])
///
/// This is a display model for bundled content, not something that
/// round-trips through a backend API.
class SafetyGuideModel {
  const SafetyGuideModel({
    required this.id,
    required this.title,
    required this.summary,
    required this.sections,
  });

  final String id;
  final String title;
  final String summary;
  final List<GuideSection> sections;

  /// Non-null for the disaster guides (flood, earthquake, ...).
  DisasterType? get disasterType => DisasterType.fromId(id);

  /// Every action across all sections -- used by callers that only care
  /// whether a guide has content.
  List<String> get allItems => [for (final s in sections) ...s.items];

  factory SafetyGuideModel.fromJson(Map<String, dynamic> json) {
    final sections = <GuideSection>[];

    final phased = json['sections'];
    if (phased is Map<String, dynamic>) {
      // Fixed display order, independent of JSON key order.
      for (final kind in const [
        GuideSectionKind.before,
        GuideSectionKind.during,
        GuideSectionKind.after,
        GuideSectionKind.avoid,
      ]) {
        final items = phased[kind.key];
        if (items is List && items.isNotEmpty) {
          sections.add(GuideSection(
            kind: kind,
            items: items.map((e) => e as String).toList(),
          ));
        }
      }
    }

    final flat = json['steps'];
    if (flat is List && flat.isNotEmpty) {
      sections.add(GuideSection(
        kind: GuideSectionKind.steps,
        items: flat.map((e) => e as String).toList(),
      ));
    }

    return SafetyGuideModel(
      id: json['id'] as String,
      title: json['title'] as String,
      summary: json['summary'] as String,
      sections: sections,
    );
  }
}
