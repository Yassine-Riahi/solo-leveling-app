import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solo_leveling_app/src/day/day.dart';
import 'package:solo_leveling_app/src/prayer/prayer.dart';
import 'package:timezone/timezone.dart' as tz;

/// 2024-06-01 12:00 UTC is 13:00 in Tunis (UTC+1, no DST), which falls inside
/// that day's Dhuhr window. Expressed in UTC so the result cannot depend on
/// the machine running the suite.
final DateTime _noonUtc = DateTime.utc(2024, 6, 1, 12);

Future<void> _pumpDayView(
  WidgetTester tester, {
  DateTime? initialDate,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: DayView(
        clock: FixedClock(_noonUtc),
        initialDate: initialDate,
      ),
    ),
  );
  await tester.pump();
}

/// Unmounts the widget so its periodic ticker does not outlive the test.
Future<void> _teardown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
}

void main() {
  testWidgets('renders all five prayer windows', (WidgetTester tester) async {
    await _pumpDayView(tester);

    for (final PrayerName name in PrayerName.values) {
      expect(
        find.byKey(Key('window-${name.name}')),
        findsOneWidget,
        reason: '${name.name} tile missing',
      );
    }
    expect(find.text('Fajr'), findsOneWidget);
    expect(find.text('Isha'), findsOneWidget);

    await _teardown(tester);
  });

  testWidgets('window height is proportional to its duration',
      (WidgetTester tester) async {
    await _pumpDayView(tester);

    final PrayerSchedule schedule = computePrayerSchedule(
      latitude: DayLocation.fallback.latitude,
      longitude: DayLocation.fallback.longitude,
      date: DateTime(2024, 6, 1),
      timeZone: DayLocation.fallback.timeZone,
    );

    // Fajr (dawn to sunrise) is short; Dhuhr runs until Asr and is far longer.
    expect(
      schedule.dhuhr.duration > schedule.fajr.duration,
      isTrue,
      reason: 'precondition: Dhuhr should outlast Fajr on this date',
    );

    final double fajrHeight =
        tester.getSize(find.byKey(const Key('window-fajr'))).height;
    final double dhuhrHeight =
        tester.getSize(find.byKey(const Key('window-dhuhr'))).height;

    expect(dhuhrHeight > fajrHeight, isTrue,
        reason: 'dhuhr $dhuhrHeight should exceed fajr $fajrHeight');

    // Heights track duration, not a fixed card size.
    final double ratio = dhuhrHeight / fajrHeight;
    final double durationRatio =
        schedule.dhuhr.duration.inMinutes / schedule.fajr.duration.inMinutes;
    expect(ratio, closeTo(durationRatio, durationRatio * 0.25));

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

  testWidgets('hides the now indicator and countdown on another day',
      (WidgetTester tester) async {
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
    await tester.pump();
    expect(find.text('2024-06-02'), findsOneWidget);
    expect(find.text('2024-06-01'), findsNothing);

    await tester.tap(find.byTooltip('Previous day'));
    await tester.pump();
    await tester.tap(find.byTooltip('Previous day'));
    await tester.pump();
    expect(find.text('2024-05-31'), findsOneWidget);

    await _teardown(tester);
  });

  testWidgets('navigating away from today hides the now indicator',
      (WidgetTester tester) async {
    await _pumpDayView(tester);
    expect(find.byKey(const Key('now-indicator')), findsOneWidget);

    await tester.tap(find.byTooltip('Next day'));
    await tester.pump();

    expect(find.byKey(const Key('now-indicator')), findsNothing);
    expect(find.byKey(const Key('countdown')), findsNothing);

    await _teardown(tester);
  });

  testWidgets('times are rendered for each window',
      (WidgetTester tester) async {
    await _pumpDayView(tester);

    // Every tile carries a "HH:mm – HH:mm" range.
    expect(find.textContaining('–'), findsNWidgets(PrayerName.values.length));

    await _teardown(tester);
  });

  testWidgets('background colour follows the window nearest the viewport '
      'centre', (WidgetTester tester) async {
    await _pumpDayView(tester);

    Color? background() {
      final AnimatedContainer container = tester.widget<AnimatedContainer>(
        find.byKey(const Key('background')),
      );
      return (container.decoration as BoxDecoration?)?.color;
    }

    // The day opens at the top, on Fajr.
    expect(background(), prayerBackgrounds[PrayerName.fajr]);

    // Dragging to the very bottom of the day lands on Isha.
    for (int i = 0; i < 4; i++) {
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -1500),
      );
      await tester.pumpAndSettle();
    }
    expect(background(), prayerBackgrounds[PrayerName.isha]);

    // And back to the top returns to Fajr.
    for (int i = 0; i < 4; i++) {
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, 1500),
      );
      await tester.pumpAndSettle();
    }
    expect(background(), prayerBackgrounds[PrayerName.fajr]);

    await _teardown(tester);
  });

  testWidgets('draws an hour grid with a labelled gutter',
      (WidgetTester tester) async {
    await _pumpDayView(tester);

    final PrayerSchedule schedule = computePrayerSchedule(
      latitude: DayLocation.fallback.latitude,
      longitude: DayLocation.fallback.longitude,
      date: DateTime(2024, 6, 1),
      timeZone: DayLocation.fallback.timeZone,
    );

    // The span runs from the hour at or before Fajr to the hour at or after
    // Isha's end, inclusive of both boundaries. Computed with zone-aware
    // arithmetic only, so the expectation cannot depend on the host's
    // timezone.
    final tz.Location location = schedule.fajr.start.location;
    tz.TZDateTime floorToHour(tz.TZDateTime moment) => tz.TZDateTime(
          location,
          moment.year,
          moment.month,
          moment.day,
          moment.hour,
        );

    final tz.TZDateTime spanStart = floorToHour(schedule.fajr.start);
    final tz.TZDateTime endFloor = floorToHour(schedule.isha.end);
    final tz.TZDateTime spanEnd = endFloor == schedule.isha.end
        ? endFloor
        : endFloor.add(const Duration(hours: 1));
    final int expectedLabels = spanEnd.difference(spanStart).inHours + 1;

    for (final String label in <String>['04:00', '12:00', '20:00']) {
      expect(find.text(label), findsOneWidget, reason: 'missing $label');
    }

    final int labelCount = tester
        .widgetList<Text>(find.byType(Text))
        .where((Text t) => RegExp(r'^\d{2}:00$').hasMatch(t.data ?? ''))
        .length;
    expect(labelCount, expectedLabels);

    await _teardown(tester);
  });
}
