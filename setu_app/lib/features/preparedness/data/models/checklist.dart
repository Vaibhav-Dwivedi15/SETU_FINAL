class ChecklistItem {
  const ChecklistItem({required this.id, required this.text, this.category});

  final String id;
  final String text;

  /// Optional grouping heading (used by the emergency kit).
  final String? category;

  factory ChecklistItem.fromJson(Map<String, dynamic> json) => ChecklistItem(
        id: json['id'] as String,
        text: json['text'] as String,
        category: json['category'] as String?,
      );
}

class Checklist {
  const Checklist({
    required this.id,
    required this.title,
    required this.description,
    required this.items,
  });

  final String id;
  final String title;
  final String description;
  final List<ChecklistItem> items;

  /// Items grouped by category in first-seen order; uncategorised items
  /// fall under a null key.
  Map<String?, List<ChecklistItem>> get itemsByCategory {
    final grouped = <String?, List<ChecklistItem>>{};
    for (final item in items) {
      grouped.putIfAbsent(item.category, () => []).add(item);
    }
    return grouped;
  }

  factory Checklist.fromJson(Map<String, dynamic> json) => Checklist(
        id: json['id'] as String,
        title: json['title'] as String,
        description: json['description'] as String? ?? '',
        items: (json['items'] as List)
            .map((e) => ChecklistItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// A checklist plus which of its items the user has ticked.
class ChecklistProgress {
  const ChecklistProgress({required this.checklist, required this.completedIds});

  final Checklist checklist;
  final Set<String> completedIds;

  int get total => checklist.items.length;
  int get completed =>
      checklist.items.where((i) => completedIds.contains(i.id)).length;
  int get remaining => total - completed;
  double get fraction => total == 0 ? 0 : completed / total;
  bool get isComplete => total > 0 && completed == total;
  bool isDone(ChecklistItem item) => completedIds.contains(item.id);
}
