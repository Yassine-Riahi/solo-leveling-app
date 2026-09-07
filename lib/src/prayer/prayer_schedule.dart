import 'package:timezone/timezone.dart' as tz;

/// The five daily obligatory prayers.
enum PrayerName { fajr, dhuhr, asr, maghrib, isha }

/// A prayer together with the interval during which it remains valid.
///
/// [start] is when the prayer becomes due and [end] is the moment it lapses.
/// A task pinned to this prayer may be moved anywhere in `[start, end]`.
class PrayerWindow {
  const PrayerWindow({
    required this.name,
    required this.start,
    required this.end,
  });

  final PrayerName name;
  final tz.TZDateTime start;
  final tz.TZDateTime end;

  /// How long the prayer remains valid.
  Duration get duration => end.difference(start);

  /// Whether [moment] falls inside the window, inclusive of both bounds.
  bool contains(tz.TZDateTime moment) =>
      !moment.isBefore(start) && !moment.isAfter(end);

  @override
  String toString() => 'PrayerWindow(${name.name}, $start – $end)';
}

/// A full day of prayer windows for one location.
class PrayerSchedule {
  const PrayerSchedule({
    required this.date,
    required this.location,
    required this.fajr,
    required this.sunrise,
    required this.dhuhr,
    required this.asr,
    required this.maghrib,
    required this.isha,
  });

  /// The local calendar day this schedule describes.
  final DateTime date;

  /// IANA timezone identifier the times are expressed in.
  final String location;

  final PrayerWindow fajr;

  /// Sunrise, which bounds Fajr but is not itself a prayer, so it carries no
  /// window of its own.
  final tz.TZDateTime sunrise;

  final PrayerWindow dhuhr;
  final PrayerWindow asr;
  final PrayerWindow maghrib;
  final PrayerWindow isha;

  /// The five windows in chronological order.
  List<PrayerWindow> get windows => <PrayerWindow>[
        fajr,
        dhuhr,
        asr,
        maghrib,
        isha,
      ];

  /// Looks up a single window by name.
  PrayerWindow operator [](PrayerName name) {
    switch (name) {
      case PrayerName.fajr:
        return fajr;
      case PrayerName.dhuhr:
        return dhuhr;
      case PrayerName.asr:
        return asr;
      case PrayerName.maghrib:
        return maghrib;
      case PrayerName.isha:
        return isha;
    }
  }
}
