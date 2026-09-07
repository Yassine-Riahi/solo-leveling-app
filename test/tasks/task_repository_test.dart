import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solo_leveling_app/src/day/day_location.dart';
import 'package:solo_leveling_app/src/prayer/prayer.dart';
import 'package:solo_leveling_app/src/tasks/tasks.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// The behaviour every [TaskRepository] must exhibit, run once per
/// implementation so the in-memory fake cannot drift from the real store.
void runRepositoryContract(
  String name,
  Future<TaskRepository> Function() create,
) {
  group('$name (repository contract)', () {
    const String zone = 'Africa/Tunis';
    final tz.Location location = tz.getLocation(zone);
    final DateTime day = DateTime(2024, 6, 1);

    Task taskAt(String id, int hour, {int minute = 0}) => Task(
          id: id,
          title: id,
          start: tz.TZDateTime(location, 2024, 6, 1, hour, minute),
          end: tz.TZDateTime(location, 2024, 6, 1, hour + 1, minute),
        );

    test('saves and reads back a task', () async {
      final TaskRepository repository = await create();
      await repository.save(taskAt('a', 9));

      final List<Task> tasks = await repository.tasksForDay(day, zone);
      expect(tasks, hasLength(1));
      expect(tasks.single.id, 'a');
      expect(tasks.single.start.hour, 9);
    });

    test('saving the same id replaces rather than duplicates', () async {
      final TaskRepository repository = await create();
      await repository.save(taskAt('a', 9));
      await repository.save(taskAt('a', 9).copyWith(title: 'renamed'));

      final List<Task> tasks = await repository.tasksForDay(day, zone);
      expect(tasks, hasLength(1));
      expect(tasks.single.title, 'renamed');
    });

    test('returns tasks ordered by start time', () async {
      final TaskRepository repository = await create();
      await repository.save(taskAt('late', 18));
      await repository.save(taskAt('early', 6));
      await repository.save(taskAt('middle', 12));

      final List<Task> tasks = await repository.tasksForDay(day, zone);
      expect(
        tasks.map((Task t) => t.id).toList(),
        <String>['early', 'middle', 'late'],
      );
    });

    test('excludes tasks belonging to another day', () async {
      final TaskRepository repository = await create();
      await repository.save(taskAt('today', 9));
      await repository.save(
        Task(
          id: 'tomorrow',
          title: 'tomorrow',
          start: tz.TZDateTime(location, 2024, 6, 2, 9),
          end: tz.TZDateTime(location, 2024, 6, 2, 10),
        ),
      );

      final List<Task> tasks = await repository.tasksForDay(day, zone);
      expect(tasks.map((Task t) => t.id), <String>['today']);
    });

    test('day boundaries are evaluated in the requested zone', () async {
      final TaskRepository repository = await create();
      // 00:30 in Tunis on 2 June is 23:30 UTC on 1 June.
      await repository.save(
        Task(
          id: 'just-after-midnight',
          title: 'x',
          start: tz.TZDateTime(location, 2024, 6, 2, 0, 30),
          end: tz.TZDateTime(location, 2024, 6, 2, 1),
        ),
      );

      expect(await repository.tasksForDay(day, zone), isEmpty);
      expect(
        await repository.tasksForDay(DateTime(2024, 6, 2), zone),
        hasLength(1),
      );
    });

    test('delete removes a task and is safe when absent', () async {
      final TaskRepository repository = await create();
      await repository.save(taskAt('a', 9));
      await repository.delete('a');
      await repository.delete('missing');

      expect(await repository.tasksForDay(day, zone), isEmpty);
    });

    test('dismissed prayer ids persist and can be restored', () async {
      final TaskRepository repository = await create();
      expect(await repository.dismissedPrayerIds(), isEmpty);

      await repository.dismissPrayer('prayer:2024-06-01:fajr');
      expect(
        await repository.dismissedPrayerIds(),
        contains('prayer:2024-06-01:fajr'),
      );

      await repository.restorePrayer('prayer:2024-06-01:fajr');
      expect(await repository.dismissedPrayerIds(), isEmpty);
    });

    test('survives a full round-trip of every field', () async {
      final TaskRepository repository = await create();
      final Task rich = taskAt('rich', 9).copyWith(
        title: 'Dhikr',
        isDone: true,
        notes: 'after Fajr',
        priority: TaskPriority.medium,
        list: 'Spiritual',
        isPrayer: true,
      );
      await repository.save(rich);

      final Task read = (await repository.tasksForDay(day, zone)).single;
      expect(read, rich);
    });
  });
}

void main() {
  tz_data.initializeTimeZones();

  runRepositoryContract(
    'InMemoryTaskRepository',
    () async => InMemoryTaskRepository(),
  );

  runRepositoryContract('PrefsTaskRepository', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    return PrefsTaskRepository(await SharedPreferences.getInstance());
  });

  group('prayer seeding', () {
    final String zone = DayLocation.fallback.timeZone;
    final DateTime day = DateTime(2024, 6, 1);

    Future<void> seed(TaskRepository repository) => seedPrayerTasks(
          repository: repository,
          day: day,
          latitude: DayLocation.fallback.latitude,
          longitude: DayLocation.fallback.longitude,
          timeZone: zone,
        );

    test('writes exactly five prayer tasks', () async {
      final TaskRepository repository = InMemoryTaskRepository();
      await seed(repository);

      final List<Task> tasks = await repository.tasksForDay(day, zone);
      expect(tasks, hasLength(5));
      expect(tasks.every((Task t) => t.isPrayer), isTrue);
      expect(
        tasks.map((Task t) => t.title).toList(),
        <String>['Fajr', 'Dhuhr', 'Asr', 'Maghrib', 'Isha'],
      );
    });

    test('is idempotent — seeding twice does not duplicate', () async {
      final TaskRepository repository = InMemoryTaskRepository();
      await seed(repository);
      await seed(repository);

      expect(await repository.tasksForDay(day, zone), hasLength(5));
    });

    test('ids are derived and stable', () async {
      final TaskRepository repository = InMemoryTaskRepository();
      await seed(repository);

      final List<Task> tasks = await repository.tasksForDay(day, zone);
      expect(tasks.first.id, 'prayer:2024-06-01:fajr');
      for (final PrayerName name in PrayerName.values) {
        expect(prayerTaskId(day, name), 'prayer:2024-06-01:${name.name}');
      }
    });

    test('seeded times match the engine', () async {
      final TaskRepository repository = InMemoryTaskRepository();
      await seed(repository);

      final PrayerSchedule schedule = computePrayerSchedule(
        latitude: DayLocation.fallback.latitude,
        longitude: DayLocation.fallback.longitude,
        date: day,
        timeZone: zone,
      );
      final List<Task> tasks = await repository.tasksForDay(day, zone);

      expect(tasks.first.start, schedule.fajr.start);
      expect(tasks.first.end, schedule.fajr.end);
      expect(tasks.last.start, schedule.isha.start);
    });

    test('re-seeding preserves every user edit but refreshes times', () async {
      final TaskRepository repository = InMemoryTaskRepository();
      await seed(repository);

      final String fajrId = prayerTaskId(day, PrayerName.fajr);
      final Task edited = (await repository.tasksForDay(day, zone))
          .firstWhere((Task t) => t.id == fajrId)
          .copyWith(
            title: 'Fajr at the mosque',
            isDone: true,
            notes: 'with jamaah',
            priority: TaskPriority.high,
            list: 'Spiritual',
          )
          // A stale time, as if the location had changed.
          .copyWith(start: tz.TZDateTime(tz.getLocation(zone), 2024, 6, 1, 1));
      await repository.save(edited);

      await seed(repository);

      final Task after = (await repository.tasksForDay(day, zone))
          .firstWhere((Task t) => t.id == fajrId);

      expect(after.title, 'Fajr at the mosque');
      expect(after.isDone, isTrue);
      expect(after.notes, 'with jamaah');
      expect(after.priority, TaskPriority.high);
      expect(after.list, 'Spiritual');

      final PrayerSchedule schedule = computePrayerSchedule(
        latitude: DayLocation.fallback.latitude,
        longitude: DayLocation.fallback.longitude,
        date: day,
        timeZone: zone,
      );
      expect(after.start, schedule.fajr.start,
          reason: 'the engine owns the clock');
      expect(after.end, schedule.fajr.end);
    });

    test('a deleted prayer stays gone across re-seeds, and can return',
        () async {
      final TaskRepository repository = InMemoryTaskRepository();
      await seed(repository);

      final String fajrId = prayerTaskId(day, PrayerName.fajr);
      await deletePrayerTask(repository: repository, id: fajrId);
      expect(await repository.tasksForDay(day, zone), hasLength(4));

      await seed(repository);
      final List<Task> afterReseed = await repository.tasksForDay(day, zone);
      expect(afterReseed, hasLength(4));
      expect(afterReseed.any((Task t) => t.id == fajrId), isFalse);

      await repository.restorePrayer(fajrId);
      await seed(repository);
      final List<Task> restored = await repository.tasksForDay(day, zone);
      expect(restored, hasLength(5));
      expect(restored.any((Task t) => t.id == fajrId), isTrue);
    });

    test('seeding leaves non-prayer tasks untouched', () async {
      final TaskRepository repository = InMemoryTaskRepository();
      final Task ordinary = Task(
        id: 'ordinary',
        title: 'Gym',
        start: tz.TZDateTime(tz.getLocation(zone), 2024, 6, 1, 17),
        end: tz.TZDateTime(tz.getLocation(zone), 2024, 6, 1, 18),
      );
      await repository.save(ordinary);
      await seed(repository);

      final List<Task> tasks = await repository.tasksForDay(day, zone);
      expect(tasks, hasLength(6));
      expect(tasks.firstWhere((Task t) => t.id == 'ordinary'), ordinary);
    });
  });
}
