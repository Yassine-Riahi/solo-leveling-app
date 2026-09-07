import 'package:timezone/timezone.dart' as tz;

import 'task.dart';
import 'task_repository.dart';

/// Non-persistent repository. Used by tests and as the reference behaviour
/// every other implementation must match.
class InMemoryTaskRepository implements TaskRepository {
  final Map<String, Task> _tasks = <String, Task>{};
  final Set<String> _dismissed = <String>{};

  @override
  Future<List<Task>> tasksForDay(DateTime day, String timeZone) async {
    final tz.Location location = tz.getLocation(timeZone);
    return sortedTasksOn(_tasks.values, day, location);
  }

  @override
  Future<void> save(Task task) async => _tasks[task.id] = task;

  @override
  Future<void> delete(String id) async => _tasks.remove(id);

  @override
  Future<Set<String>> dismissedPrayerIds() async => Set<String>.of(_dismissed);

  @override
  Future<void> dismissPrayer(String id) async => _dismissed.add(id);

  @override
  Future<void> restorePrayer(String id) async => _dismissed.remove(id);
}

/// Tasks starting on [day] in [location], ordered by start time.
///
/// Shared by every repository so the day-boundary rule has one definition.
List<Task> sortedTasksOn(
  Iterable<Task> tasks,
  DateTime day,
  tz.Location location,
) {
  final tz.TZDateTime dayStart =
      tz.TZDateTime(location, day.year, day.month, day.day);
  final tz.TZDateTime dayEnd = dayStart.add(const Duration(days: 1));

  final List<Task> matching = tasks.where((Task task) {
    final tz.TZDateTime start = tz.TZDateTime.from(task.start, location);
    return !start.isBefore(dayStart) && start.isBefore(dayEnd);
  }).toList();

  matching.sort((Task a, Task b) => a.start.compareTo(b.start));
  return matching;
}
