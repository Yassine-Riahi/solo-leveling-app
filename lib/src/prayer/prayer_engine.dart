import 'package:adhan_dart/adhan_dart.dart' as adhan;
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'prayer_schedule.dart';
import 'prayer_settings.dart';

bool _timeZonesReady = false;

/// Loads the bundled IANA timezone database exactly once.
///
/// The data ships compiled into the `timezone` package, so this touches no
/// files and performs no network access.
void _ensureTimeZones() {
  if (_timeZonesReady) return;
  tz_data.initializeTimeZones();
  _timeZonesReady = true;
}

/// Computes the prayer schedule for one calendar day at one location.
///
/// [date] is interpreted as a local calendar day in [timeZone]; its own time
/// component and timezone are ignored. [timeZone] is an IANA identifier such
/// as `Africa/Tunis`. Every returned time is a [tz.TZDateTime] in that zone,
/// so results never depend on the host machine's system timezone.
///
/// The function is pure: it reads no device state, performs no I/O, and
/// retains nothing between calls.
PrayerSchedule computePrayerSchedule({
  required double latitude,
  required double longitude,
  required DateTime date,
  required String timeZone,
  PrayerSettings settings = const PrayerSettings(),
}) {
  _ensureTimeZones();
  final tz.Location location = tz.getLocation(timeZone);

  final DateTime utcDate = DateTime.utc(date.year, date.month, date.day);
  final adhan.PrayerTimes times = _resolveTimes(
    latitude: latitude,
    longitude: longitude,
    utcDate: utcDate,
    settings: settings,
  );

  tz.TZDateTime at(DateTime utc) => tz.TZDateTime.from(utc, location);

  final tz.TZDateTime fajr = at(times.fajr);
  final tz.TZDateTime sunrise = at(times.sunrise);
  final tz.TZDateTime dhuhr = at(times.dhuhr);
  final tz.TZDateTime asr = at(times.asr);
  final tz.TZDateTime maghrib = at(times.maghrib);
  final tz.TZDateTime isha = at(times.isha);
  final tz.TZDateTime fajrTomorrow = at(times.fajrAfter);

  return PrayerSchedule(
    date: DateTime(date.year, date.month, date.day),
    location: timeZone,
    fajr: PrayerWindow(name: PrayerName.fajr, start: fajr, end: sunrise),
    sunrise: sunrise,
    dhuhr: PrayerWindow(name: PrayerName.dhuhr, start: dhuhr, end: asr),
    asr: PrayerWindow(name: PrayerName.asr, start: asr, end: maghrib),
    maghrib: PrayerWindow(name: PrayerName.maghrib, start: maghrib, end: isha),
    isha: PrayerWindow(
      name: PrayerName.isha,
      start: isha,
      end: _ishaEnd(maghrib: maghrib, isha: isha, fajrTomorrow: fajrTomorrow),
    ),
  );
}

/// Widest plausible spread between a day's first and last prayer, used to
/// recognise a schedule that has drifted off the requested date.
const Duration _maxDrift = Duration(hours: 36);

/// Computes prayer times, working around an upstream polar-circle defect.
///
/// Inside the polar circle adhan_dart only applies its own resolution when the
/// solar values come back as NaN. During the polar day they are finite but out
/// of range instead, so the guard never fires and the returned times drift
/// weeks away from the requested date.
///
/// This reproduces the library's documented `aqrabBalad` strategy with a
/// predicate that actually detects the condition: step the latitude toward the
/// equator until the day resolves into an ordered schedule. Coordinates are
/// only ever adjusted when the requested ones yield no usable day.
adhan.PrayerTimes _resolveTimes({
  required double latitude,
  required double longitude,
  required DateTime utcDate,
  required PrayerSettings settings,
}) {
  final adhan.CalculationParameters parameters = _parametersFor(settings);
  final double sign = latitude.isNegative ? -1 : 1;

  for (double candidate = latitude.abs();
      candidate >= 0;
      candidate -= 0.5) {
    final adhan.PrayerTimes times = adhan.PrayerTimes(
      date: utcDate,
      coordinates: adhan.Coordinates(sign * candidate, longitude),
      calculationParameters: parameters,
    );
    if (_isWellFormed(times, utcDate)) return times;
  }

  // Unreachable in practice: the equator always resolves. Returning the
  // equatorial result is still preferable to throwing, per AC-5.
  return adhan.PrayerTimes(
    date: utcDate,
    coordinates: adhan.Coordinates(0, longitude),
    calculationParameters: parameters,
  );
}

/// Whether [times] forms a single ordered day anchored to [utcDate].
bool _isWellFormed(adhan.PrayerTimes times, DateTime utcDate) {
  final List<DateTime> ordered = <DateTime>[
    times.fajr,
    times.sunrise,
    times.dhuhr,
    times.asr,
    times.maghrib,
    times.isha,
    times.fajrAfter,
  ];

  for (final DateTime time in ordered) {
    if (time.difference(utcDate).abs() > _maxDrift) return false;
  }
  for (int i = 1; i < ordered.length; i++) {
    if (!ordered[i].isAfter(ordered[i - 1])) return false;
  }
  return true;
}

/// Islamic midnight: the midpoint between Maghrib and the following Fajr.
///
/// Near the poles the high-latitude fallback can push Isha past that midpoint,
/// which would produce a window ending before it starts. In that case the
/// following Fajr is used instead, so the window stays ordered and usable.
tz.TZDateTime _ishaEnd({
  required tz.TZDateTime maghrib,
  required tz.TZDateTime isha,
  required tz.TZDateTime fajrTomorrow,
}) {
  final Duration night = fajrTomorrow.difference(maghrib);
  final tz.TZDateTime midnight = maghrib.add(night ~/ 2);
  return midnight.isAfter(isha) ? midnight : fajrTomorrow;
}

adhan.CalculationParameters _parametersFor(PrayerSettings settings) {
  final adhan.CalculationParameters parameters;
  switch (settings.method) {
    case PrayerCalculationMethod.muslimWorldLeague:
      parameters = adhan.CalculationMethodParameters.muslimWorldLeague();
    case PrayerCalculationMethod.ummAlQura:
      parameters = adhan.CalculationMethodParameters.ummAlQura();
    case PrayerCalculationMethod.egyptian:
      parameters = adhan.CalculationMethodParameters.egyptian();
    case PrayerCalculationMethod.isna:
      parameters = adhan.CalculationMethodParameters.northAmerica();
    case PrayerCalculationMethod.karachi:
      parameters = adhan.CalculationMethodParameters.karachi();
  }

  parameters.madhab = switch (settings.madhab) {
    AsrMadhab.shafi => adhan.Madhab.shafi,
    AsrMadhab.hanafi => adhan.Madhab.hanafi,
  };

  parameters.highLatitudeRule = switch (settings.highLatitudeFallback) {
    HighLatitudeFallback.middleOfTheNight =>
      adhan.HighLatitudeRule.middleOfTheNight,
    HighLatitudeFallback.seventhOfTheNight =>
      adhan.HighLatitudeRule.seventhOfTheNight,
    HighLatitudeFallback.twilightAngle => adhan.HighLatitudeRule.twilightAngle,
  };

  // Inside the polar circle the sun may never rise or set, leaving sunrise and
  // sunset undefined; left unresolved, adhan_dart returns times drifting weeks
  // away from the requested day. `aqrabBalad` nudges the latitude toward the
  // equator until the day resolves, which keeps every returned time on the
  // requested calendar date — essential for a day-view calendar. The
  // alternative, `aqrabYaum`, borrows times from a different date entirely.
  parameters.polarCircleResolution = adhan.PolarCircleResolution.aqrabBalad;

  return parameters;
}
