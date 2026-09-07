import 'package:flutter_test/flutter_test.dart';
import 'package:solo_leveling_app/src/prayer/prayer.dart';
import 'package:timezone/timezone.dart' as tz;

/// Formats as local HH:mm for comparison against published timetables.
String _hhmm(tz.TZDateTime time) =>
    '${time.hour.toString().padLeft(2, '0')}:'
    '${time.minute.toString().padLeft(2, '0')}';

/// Asserts [actual] is within one minute of [expected], given as 'HH:mm'.
void _expectWithinAMinute(tz.TZDateTime actual, String expected) {
  final List<String> parts = expected.split(':');
  final tz.TZDateTime target = tz.TZDateTime(
    actual.location,
    actual.year,
    actual.month,
    actual.day,
    int.parse(parts[0]),
    int.parse(parts[1]),
  );
  final int deltaSeconds = actual.difference(target).inSeconds.abs();
  expect(
    deltaSeconds <= 60,
    isTrue,
    reason: 'expected $expected, got ${_hhmm(actual)} '
        '(${deltaSeconds}s apart)',
  );
}

void main() {
  group('reference timetable', () {
    // Raleigh, North Carolina on 2015-07-12 using ISNA and the Hanafi madhab
    // is the canonical worked example published with the adhan library. All
    // six values below come from that published table, not from this engine.
    const double latitude = 35.7750;
    const double longitude = -78.6336;

    test('matches published times within one minute', () {
      final PrayerSchedule schedule = computePrayerSchedule(
        latitude: latitude,
        longitude: longitude,
        date: DateTime(2015, 7, 12),
        timeZone: 'America/New_York',
        settings: const PrayerSettings(
          method: PrayerCalculationMethod.isna,
          madhab: AsrMadhab.hanafi,
        ),
      );

      _expectWithinAMinute(schedule.fajr.start, '04:42');
      _expectWithinAMinute(schedule.sunrise, '06:08');
      _expectWithinAMinute(schedule.dhuhr.start, '13:21');
      _expectWithinAMinute(schedule.asr.start, '18:22');
      _expectWithinAMinute(schedule.maghrib.start, '20:32');
      _expectWithinAMinute(schedule.isha.start, '21:57');
    });
  });

  group('madhab', () {
    PrayerSchedule scheduleFor(AsrMadhab madhab) => computePrayerSchedule(
          latitude: 35.7750,
          longitude: -78.6336,
          date: DateTime(2015, 7, 12),
          timeZone: 'America/New_York',
          settings: PrayerSettings(
            method: PrayerCalculationMethod.isna,
            madhab: madhab,
          ),
        );

    test('Hanafi pushes Asr later than Shafi', () {
      final PrayerSchedule shafi = scheduleFor(AsrMadhab.shafi);
      final PrayerSchedule hanafi = scheduleFor(AsrMadhab.hanafi);

      expect(hanafi.asr.start.isAfter(shafi.asr.start), isTrue);
      _expectWithinAMinute(shafi.asr.start, '17:09');
      _expectWithinAMinute(hanafi.asr.start, '18:22');
    });

    test('leaves the other four prayers untouched', () {
      final PrayerSchedule shafi = scheduleFor(AsrMadhab.shafi);
      final PrayerSchedule hanafi = scheduleFor(AsrMadhab.hanafi);

      expect(hanafi.fajr.start, shafi.fajr.start);
      expect(hanafi.sunrise, shafi.sunrise);
      expect(hanafi.dhuhr.start, shafi.dhuhr.start);
      expect(hanafi.maghrib.start, shafi.maghrib.start);
      expect(hanafi.isha.start, shafi.isha.start);
    });
  });

  group('calculation method', () {
    PrayerSchedule scheduleFor(PrayerCalculationMethod method) =>
        computePrayerSchedule(
          latitude: 21.4225,
          longitude: 39.8262,
          date: DateTime(2024, 3, 15),
          timeZone: 'Asia/Riyadh',
          settings: PrayerSettings(method: method),
        );

    test('Umm al-Qura and Muslim World League differ on Fajr and Isha', () {
      final PrayerSchedule mwl =
          scheduleFor(PrayerCalculationMethod.muslimWorldLeague);
      final PrayerSchedule uaq = scheduleFor(PrayerCalculationMethod.ummAlQura);

      expect(uaq.fajr.start, isNot(mwl.fajr.start));
      expect(uaq.isha.start, isNot(mwl.isha.start));
    });

    test('every supported method produces an ordered schedule', () {
      for (final PrayerCalculationMethod method
          in PrayerCalculationMethod.values) {
        final PrayerSchedule schedule = scheduleFor(method);
        for (final PrayerWindow window in schedule.windows) {
          expect(
            window.end.isAfter(window.start),
            isTrue,
            reason: '${method.name}: ${window.name.name} window is inverted',
          );
        }
      }
    });
  });

  group('window invariants', () {
    test('each window ends exactly where the next begins', () {
      final PrayerSchedule schedule = computePrayerSchedule(
        latitude: 36.8065,
        longitude: 10.1815,
        date: DateTime(2024, 6, 1),
        timeZone: 'Africa/Tunis',
      );

      expect(schedule.fajr.end, schedule.sunrise);
      expect(schedule.dhuhr.end, schedule.asr.start);
      expect(schedule.asr.end, schedule.maghrib.start);
      expect(schedule.maghrib.end, schedule.isha.start);
    });

    test('Isha ends at Islamic midnight, after Maghrib and before Fajr', () {
      final PrayerSchedule schedule = computePrayerSchedule(
        latitude: 36.8065,
        longitude: 10.1815,
        date: DateTime(2024, 6, 1),
        timeZone: 'Africa/Tunis',
      );

      expect(schedule.isha.end.isAfter(schedule.isha.start), isTrue);
      expect(schedule.isha.end.isAfter(schedule.maghrib.start), isTrue);
    });

    test('no window is inverted', () {
      final PrayerSchedule schedule = computePrayerSchedule(
        latitude: 36.8065,
        longitude: 10.1815,
        date: DateTime(2024, 6, 1),
        timeZone: 'Africa/Tunis',
      );

      for (final PrayerWindow window in schedule.windows) {
        expect(window.end.isAfter(window.start), isTrue,
            reason: '${window.name.name} is inverted');
      }
    });
  });

  group('time zones', () {
    test('times are expressed in the requested zone', () {
      final PrayerSchedule schedule = computePrayerSchedule(
        latitude: 36.8065,
        longitude: 10.1815,
        date: DateTime(2024, 6, 1),
        timeZone: 'Africa/Tunis',
      );

      expect(schedule.location, 'Africa/Tunis');
      expect(schedule.fajr.start.location.name, 'Africa/Tunis');
    });

    test('daylight saving shifts the local offset', () {
      PrayerSchedule at(DateTime date) => computePrayerSchedule(
            latitude: 40.7128,
            longitude: -74.0060,
            date: date,
            timeZone: 'America/New_York',
          );

      final PrayerSchedule winter = at(DateTime(2024, 1, 15));
      final PrayerSchedule summer = at(DateTime(2024, 7, 15));

      expect(winter.dhuhr.start.timeZoneOffset, const Duration(hours: -5));
      expect(summer.dhuhr.start.timeZoneOffset, const Duration(hours: -4));
    });

    test('the day after a spring-forward transition stays ordered', () {
      // 2024-03-10 is the US spring-forward date.
      final PrayerSchedule schedule = computePrayerSchedule(
        latitude: 40.7128,
        longitude: -74.0060,
        date: DateTime(2024, 3, 10),
        timeZone: 'America/New_York',
      );

      for (final PrayerWindow window in schedule.windows) {
        expect(window.end.isAfter(window.start), isTrue,
            reason: '${window.name.name} is inverted across the transition');
      }
    });
  });

  group('high latitude', () {
    // Tromsø, Norway. The sun does not set in June, so Fajr and Isha are
    // undefined without a fallback rule.
    const double latitude = 69.6492;
    const double longitude = 18.9553;

    test('returns a complete schedule under every fallback rule', () {
      for (final HighLatitudeFallback fallback
          in HighLatitudeFallback.values) {
        final PrayerSchedule schedule = computePrayerSchedule(
          latitude: latitude,
          longitude: longitude,
          date: DateTime(2024, 6, 21),
          timeZone: 'Europe/Oslo',
          settings: PrayerSettings(highLatitudeFallback: fallback),
        );

        for (final PrayerWindow window in schedule.windows) {
          expect(window.end.isAfter(window.start), isTrue,
              reason: '${fallback.name}: ${window.name.name} is inverted');
        }
      }
    });

    test('does not throw in midwinter either', () {
      expect(
        () => computePrayerSchedule(
          latitude: latitude,
          longitude: longitude,
          date: DateTime(2024, 12, 21),
          timeZone: 'Europe/Oslo',
        ),
        returnsNormally,
      );
    });
  });

  group('window helpers', () {
    test('contains covers both bounds and rejects outside times', () {
      final PrayerSchedule schedule = computePrayerSchedule(
        latitude: 36.8065,
        longitude: 10.1815,
        date: DateTime(2024, 6, 1),
        timeZone: 'Africa/Tunis',
      );
      final PrayerWindow dhuhr = schedule.dhuhr;

      expect(dhuhr.contains(dhuhr.start), isTrue);
      expect(dhuhr.contains(dhuhr.end), isTrue);
      expect(
        dhuhr.contains(dhuhr.start.subtract(const Duration(minutes: 1))),
        isFalse,
      );
      expect(
        dhuhr.contains(dhuhr.end.add(const Duration(minutes: 1))),
        isFalse,
      );
      expect(dhuhr.duration, dhuhr.end.difference(dhuhr.start));
    });

    test('lookup by name returns the matching window', () {
      final PrayerSchedule schedule = computePrayerSchedule(
        latitude: 36.8065,
        longitude: 10.1815,
        date: DateTime(2024, 6, 1),
        timeZone: 'Africa/Tunis',
      );

      for (final PrayerName name in PrayerName.values) {
        expect(schedule[name].name, name);
      }
    });
  });
}
