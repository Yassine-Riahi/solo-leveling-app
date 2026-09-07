import 'package:timezone/timezone.dart' as tz;

import '../prayer/prayer.dart';
import 'task.dart';
import 'task_repository.dart';

/// Stable identity for a prayer task: derived from the date and prayer, never
/// random, so re-seeding updates the same row instead of adding a duplicate.
String prayerTaskId(DateTime day, PrayerName prayer) {
  final String date = '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';
  return 'prayer:$date:${prayer.name}';
}

/// Default title for a prayer task.
String defaultPrayerTitle(PrayerName prayer) {
  switch (prayer) {
    case PrayerName.fajr:
      return 'Fajr';
    case PrayerName.dhuhr:
      return 'Dhuhr';
    case PrayerName.asr:
      return 'Asr';
    case PrayerName.maghrib:
      return 'Maghrib';
    case PrayerName.isha:
      return 'Isha';
  }
}

/// Writes the five prayers for [day] into [repository] as real tasks.
///
/// The engine owns the clock and the user owns the content: re-seeding
/// overwrites only `start` and `end` on a prayer task that already exists, so
/// an edited title, notes, priority, list and completion all survive.
///
/// Prayer ids the user has dismissed are skipped, so a deleted prayer stays
/// deleted across re-seeds.
Future<void> seedPrayerTasks({
  required TaskRepository repository,
  required DateTime day,
  required double latitude,
  required double longitude,
  required String timeZone,
  PrayerSettings settings = const PrayerSettings(),
}) async {
  final PrayerSchedule schedule = computePrayerSchedule(
    latitude: latitude,
    longitude: longitude,
    date: day,
    timeZone: timeZone,
    settings: settings,
  );

  final Set<String> dismissed = await repository.dismissedPrayerIds();
  final List<Task> existing = await repository.tasksForDay(day, timeZone);
  final Map<String, Task> byId = <String, Task>{
    for (final Task task in existing) task.id: task,
  };

  for (final PrayerWindow window in schedule.windows) {
    final String id = prayerTaskId(day, window.name);
    if (dismissed.contains(id)) continue;

    final Task? current = byId[id];
    final Task next = current == null
        ? Task(
            id: id,
            title: defaultPrayerTitle(window.name),
            start: window.start,
            end: window.end,
            isPrayer: true,
          )
        // Times only; everything the user may have edited is preserved.
        : current.copyWith(start: window.start, end: window.end);

    await repository.save(next);
  }
}

/// Deletes a prayer task and records the dismissal so seeding will not bring
/// it back. Use [TaskRepository.restorePrayer] to undo.
Future<void> deletePrayerTask({
  required TaskRepository repository,
  required String id,
}) async {
  await repository.delete(id);
  await repository.dismissPrayer(id);
}

/// Convenience: the zone-aware start of [day] in [timeZone].
tz.TZDateTime startOfDay(DateTime day, String timeZone) => tz.TZDateTime(
      tz.getLocation(timeZone),
      day.year,
      day.month,
      day.day,
    );
