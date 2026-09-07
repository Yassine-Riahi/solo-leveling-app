import 'package:timezone/timezone.dart' as tz;

/// How urgent a task is. Ordered from [none] to [high].
enum TaskPriority { none, low, medium, high }

/// A single scheduled item on a day.
///
/// Immutable: every change produces a new instance via [copyWith]. Times are
/// zone-aware, and serialise to ISO-8601 UTC so stored data never depends on
/// the device's timezone.
class Task {
  const Task({
    required this.id,
    required this.title,
    required this.start,
    required this.end,
    this.isDone = false,
    this.notes,
    this.priority = TaskPriority.none,
    this.list,
    this.isPrayer = false,
  });

  /// Stable identity. Prayer tasks derive theirs; see [prayerTaskId].
  final String id;
  final String title;
  final tz.TZDateTime start;
  final tz.TZDateTime end;
  final bool isDone;
  final String? notes;
  final TaskPriority priority;

  /// Name of the list this task belongs to, if any.
  final String? list;

  /// Whether this task was generated from the prayer engine.
  final bool isPrayer;

  Duration get duration => end.difference(start);

  Task copyWith({
    String? title,
    tz.TZDateTime? start,
    tz.TZDateTime? end,
    bool? isDone,
    String? notes,
    bool clearNotes = false,
    TaskPriority? priority,
    String? list,
    bool clearList = false,
    bool? isPrayer,
  }) {
    return Task(
      id: id,
      title: title ?? this.title,
      start: start ?? this.start,
      end: end ?? this.end,
      isDone: isDone ?? this.isDone,
      notes: clearNotes ? null : (notes ?? this.notes),
      priority: priority ?? this.priority,
      list: clearList ? null : (list ?? this.list),
      isPrayer: isPrayer ?? this.isPrayer,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'start': start.toUtc().toIso8601String(),
        'end': end.toUtc().toIso8601String(),
        'isDone': isDone,
        'notes': notes,
        'priority': priority.name,
        'list': list,
        'isPrayer': isPrayer,
      };

  /// Rebuilds a task, expressing its times in [location].
  factory Task.fromJson(Map<String, dynamic> json, tz.Location location) {
    tz.TZDateTime at(String iso) =>
        tz.TZDateTime.from(DateTime.parse(iso), location);

    return Task(
      id: json['id'] as String,
      title: json['title'] as String,
      start: at(json['start'] as String),
      end: at(json['end'] as String),
      isDone: json['isDone'] as bool? ?? false,
      notes: json['notes'] as String?,
      priority: TaskPriority.values.firstWhere(
        (TaskPriority p) => p.name == json['priority'],
        orElse: () => TaskPriority.none,
      ),
      list: json['list'] as String?,
      isPrayer: json['isPrayer'] as bool? ?? false,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Task &&
      other.id == id &&
      other.title == title &&
      other.start == start &&
      other.end == end &&
      other.isDone == isDone &&
      other.notes == notes &&
      other.priority == priority &&
      other.list == list &&
      other.isPrayer == isPrayer;

  @override
  int get hashCode =>
      Object.hash(id, title, start, end, isDone, notes, priority, list,
          isPrayer);

  @override
  String toString() => 'Task($id, $title, $start – $end, done: $isDone)';
}
