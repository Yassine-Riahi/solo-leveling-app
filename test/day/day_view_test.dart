import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solo_leveling_app/src/day/day.dart';
import 'package:solo_leveling_app/src/day/task_layout.dart';
import 'package:solo_leveling_app/src/prayer/prayer.dart';
import 'package:solo_leveling_app/src/tasks/tasks.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// 2024-06-01 12:00 UTC is 13:00 in Tunis (UTC+1, no DST), inside that day's
/// Dhuhr window. Expressed in UTC so results cannot depend on the host zone.
final DateTime _noonUtc = DateTime.utc(2024, 6, 1, 12);
final DateTime _day = DateTime(2024, 6, 1);

late tz.Location _tunis;

Future<InMemoryTaskRepository> _pumpDayView(
  WidgetTester tester, {
  DateTime? initialDate,
  List<Task> extraTasks = const <Task>[],
}) async {
  final InMemoryTaskRepository repository = InMemoryTaskRepository();
  for (final Task task in extraTasks) {
    await repository.save(task);
  }

  await tester.pumpWidget(
    MaterialApp(
      home: DayView(
        repository: repository,
        clock: FixedClock(_noonUtc),
        initialDate: initialDate,
      ),
    ),
  );
  // Let seeding and the first read settle.
  await tester.pumpAndSettle();
  return repository;
}

/// Unmounts the widget so its periodic ticker does not outlive the test.
Future<void> _teardown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
}

Task _task(
  String id,
  int startHour,
  int endHour, {
  String? title,
  bool isDone = false,
}) =>
    Task(
      id: id,
      title: title ?? id,
      start: tz.TZDateTime(_tunis, 2024, 6, 1, startHour),
      end: tz.TZDateTime(_tunis, 2024, 6, 1, endHour),
      isDone: isDone,
    );

void main() {
  tz_data.initializeTimeZones();
  _tunis = tz.getLocation('Africa/Tunis');

  group('rendering from storage', () {
    testWidgets('renders the five seeded prayers', (WidgetTester tester) async {
      await _pumpDayView(tester);

      for (final PrayerName name in PrayerName.values) {
        expect(
          find.byKey(Key('task-${prayerTaskId(_day, name)}')),
          findsOneWidget,
          reason: '${name.name} tile missing',
        );
      }
      expect(find.text('Fajr'), findsOneWidget);
      expect(find.text('Isha'), findsOneWidget);

      await _teardown(tester);
    });

    testWidgets('renders an ordinary stored task alongside the prayers',
        (WidgetTester tester) async {
      await _pumpDayView(
        tester,
        extraTasks: <Task>[_task('gym', 16, 17, title: 'Gym')],
      );

      expect(find.byKey(const Key('task-gym')), findsOneWidget);
      expect(find.text('Gym'), findsOneWidget);

      await _teardown(tester);
    });

    testWidgets('prayer tasks are marked and ordinary ones are not',
        (WidgetTester tester) async {
      await _pumpDayView(
        tester,
        extraTasks: <Task>[_task('gym', 16, 17, title: 'Gym')],
      );

      final String fajrId = prayerTaskId(_day, PrayerName.fajr);
      expect(find.byKey(Key('prayer-mark-$fajrId')), findsOneWidget);
      expect(find.byKey(const Key('prayer-mark-gym')), findsNothing);

      await _teardown(tester);
    });

    testWidgets('a completed task is visibly distinct',
        (WidgetTester tester) async {
      await _pumpDayView(
        tester,
        extraTasks: <Task>[
          _task('done-task', 16, 17, title: 'Read', isDone: true),
          _task('open-task', 19, 20, title: 'Walk'),
        ],
      );

      expect(find.byKey(const Key('done-done-task')), findsOneWidget);
      expect(find.byKey(const Key('done-open-task')), findsNothing);

      final Text completed = tester.widget<Text>(find.text('Read'));
      final Text open = tester.widget<Text>(find.text('Walk'));
      expect(completed.style?.decoration, TextDecoration.lineThrough);
      expect(open.style?.decoration, TextDecoration.none);

      await _teardown(tester);
    });
  });

  group('overlap layout', () {
    testWidgets('overlapping tasks sit side by side, not stacked',
        (WidgetTester tester) async {
      await _pumpDayView(
        tester,
        extraTasks: <Task>[
          _task('a', 16, 18, title: 'A'),
          _task('b', 17, 19, title: 'B'),
        ],
      );

      final Rect a = tester.getRect(find.byKey(const Key('task-a')));
      final Rect b = tester.getRect(find.byKey(const Key('task-b')));

      // They overlap in time...
      expect(a.top < b.bottom && b.top < a.bottom, isTrue);
      // ...so they must not overlap horizontally.
      expect(
        a.right <= b.left + 1 || b.right <= a.left + 1,
        isTrue,
        reason: 'a=$a b=$b overlap horizontally',
      );

      await _teardown(tester);
    });

    testWidgets('a task with no overlap keeps the full content width',
        (WidgetTester tester) async {
      await _pumpDayView(
        tester,
        // 09:00–10:00 falls in the gap between sunrise and Dhuhr, so it
        // overlaps no prayer window and should keep the full width.
        extraTasks: <Task>[_task('solo', 9, 10, title: 'Solo')],
      );

      final Rect solo = tester.getRect(find.byKey(const Key('task-solo')));
      final Rect fajr = tester.getRect(
        find.byKey(Key('task-${prayerTaskId(_day, PrayerName.fajr)}')),
      );
      expect(solo.width, closeTo(fajr.width, 1));

      await _teardown(tester);
    });
  });

  group('layOutTasks', () {
    test('packs a chain of overlaps into the fewest lanes', () {
      final List<Task> tasks = <Task>[
        _task('a', 9, 11),
        _task('b', 10, 12),
        _task('c', 12, 13),
      ];

      final List<LaidOutTask> laid = layOutTasks(tasks);
      final Map<String, LaidOutTask> byId = <String, LaidOutTask>{
        for (final LaidOutTask l in laid) l.task.id: l,
      };

      expect(byId['a']!.lane, isNot(byId['b']!.lane));
      expect(byId['a']!.laneCount, 2);
      // 'c' starts after both end, so it is its own cluster at full width.
      expect(byId['c']!.laneCount, 1);
    });

    test('reuses a lane once it is free', () {
      final List<Task> tasks = <Task>[
        _task('a', 9, 11),
        _task('b', 10, 12),
        _task('c', 11, 13),
      ];
      final Map<String, LaidOutTask> byId = <String, LaidOutTask>{
        for (final LaidOutTask l in layOutTasks(tasks)) l.task.id: l,
      };

      // 'c' can take the lane 'a' vacated at 11:00.
      expect(byId['c']!.lane, byId['a']!.lane);
      expect(byId['c']!.laneCount, 2);
    });

    test('handles an empty list', () {
      expect(layOutTasks(const <Task>[]), isEmpty);
    });
  });

  group('preserved behaviour', () {
    testWidgets('block height is proportional to duration',
        (WidgetTester tester) async {
      await _pumpDayView(tester);

      final PrayerSchedule schedule = computePrayerSchedule(
        latitude: DayLocation.fallback.latitude,
        longitude: DayLocation.fallback.longitude,
        date: _day,
        timeZone: DayLocation.fallback.timeZone,
      );
      expect(schedule.dhuhr.duration > schedule.fajr.duration, isTrue);

      final double fajr = tester
          .getSize(find.byKey(Key('task-${prayerTaskId(_day, PrayerName.fajr)}')))
          .height;
      final double dhuhr = tester
          .getSize(
              find.byKey(Key('task-${prayerTaskId(_day, PrayerName.dhuhr)}')))
          .height;

      expect(dhuhr > fajr, isTrue);
      final double durationRatio =
          schedule.dhuhr.duration.inMinutes / schedule.fajr.duration.inMinutes;
      expect(dhuhr / fajr, closeTo(durationRatio, durationRatio * 0.25));

      await _teardown(tester);
    });

    testWidgets('shows the now indicator and countdown for today',
        (WidgetTester tester) async {
      await _pumpDayView(tester);

      expect(find.byKey(const Key('now-indicator')), findsOneWidget);
      expect(find.byKey(const Key('countdown')), findsOneWidget);
      expect(find.textContaining('left in'), findsOneWidget);

      await _teardown(tester);
    });

    testWidgets('hides both on another day', (WidgetTester tester) async {
      await _pumpDayView(tester, initialDate: DateTime(2024, 6, 5));

      expect(find.byKey(const Key('now-indicator')), findsNothing);
      expect(find.byKey(const Key('countdown')), findsNothing);

      await _teardown(tester);
    });

    testWidgets('day navigation moves the rendered date',
        (WidgetTester tester) async {
      await _pumpDayView(tester);
      expect(find.text('2024-06-01'), findsOneWidget);

      await tester.tap(find.byTooltip('Next day'));
      await tester.pumpAndSettle();
      expect(find.text('2024-06-02'), findsOneWidget);
      expect(find.byKey(const Key('now-indicator')), findsNothing);

      await tester.tap(find.byTooltip('Previous day'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Previous day'));
      await tester.pumpAndSettle();
      expect(find.text('2024-05-31'), findsOneWidget);

      await _teardown(tester);
    });

    testWidgets('navigating seeds the new day too',
        (WidgetTester tester) async {
      final InMemoryTaskRepository repository = await _pumpDayView(tester);

      await tester.tap(find.byTooltip('Next day'));
      await tester.pumpAndSettle();

      final List<Task> next = await repository.tasksForDay(
        DateTime(2024, 6, 2),
        DayLocation.fallback.timeZone,
      );
      expect(next, hasLength(5));

      await _teardown(tester);
    });

    testWidgets('draws an hour grid with a labelled gutter',
        (WidgetTester tester) async {
      await _pumpDayView(tester);

      for (final String label in <String>['04:00', '12:00', '20:00']) {
        expect(find.text(label), findsOneWidget, reason: 'missing $label');
      }

      await _teardown(tester);
    });

    testWidgets('background follows the window nearest the viewport centre',
        (WidgetTester tester) async {
      await _pumpDayView(tester);

      Color? background() {
        final AnimatedContainer container = tester.widget<AnimatedContainer>(
          find.byKey(const Key('background')),
        );
        return (container.decoration as BoxDecoration?)?.color;
      }

      expect(background(), prayerBackgrounds[PrayerName.fajr]);

      for (int i = 0; i < 4; i++) {
        await tester.drag(
          find.byType(SingleChildScrollView),
          const Offset(0, -1500),
        );
        await tester.pumpAndSettle();
      }
      expect(background(), prayerBackgrounds[PrayerName.isha]);

      await _teardown(tester);
    });
  });
}
