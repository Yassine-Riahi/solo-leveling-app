import 'task.dart';

/// Storage for tasks and for the prayer ids the user has dismissed.
///
/// Deliberately storage-agnostic: no implementation detail appears in any
/// signature, so the backing store can change without touching callers.
abstract class TaskRepository {
  /// Tasks whose start falls on [day] in [timeZone], ordered by start time.
  Future<List<Task>> tasksForDay(DateTime day, String timeZone);

  /// Inserts or replaces the task with this id.
  Future<void> save(Task task);

  /// Removes the task with [id]. Does nothing when it is absent.
  Future<void> delete(String id);

  /// Ids of prayer tasks the user has deleted, which seeding must not recreate.
  Future<Set<String>> dismissedPrayerIds();

  /// Marks a prayer id as dismissed so re-seeding skips it.
  Future<void> dismissPrayer(String id);

  /// Undoes [dismissPrayer], allowing the prayer to be seeded again.
  Future<void> restorePrayer(String id);
}
