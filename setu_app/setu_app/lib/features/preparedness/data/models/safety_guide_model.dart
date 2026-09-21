/// One disaster-type safety guide (flood, fire, earthquake, ...).
///
/// Deliberately as small as ContactModel elsewhere in this codebase --
/// this is a display model for bundled, offline content, not something
/// that round-trips through a backend API.
class SafetyGuideModel {
  final String id;
  final String title;
  final String summary;
  final List<String> steps;

  const SafetyGuideModel({
    required this.id,
    required this.title,
    required this.summary,
    required this.steps,
  });

  factory SafetyGuideModel.fromJson(Map<String, dynamic> json) {
    return SafetyGuideModel(
      id: json['id'] as String,
      title: json['title'] as String,
      summary: json['summary'] as String,
      steps: (json['steps'] as List).map((step) => step as String).toList(),
    );
  }
}
