/// Calculation methods supported by the engine.
///
/// Each maps onto a set of Fajr/Isha twilight angles published by the
/// corresponding authority.
enum PrayerCalculationMethod {
  muslimWorldLeague,
  ummAlQura,
  egyptian,

  /// ISNA, published by the Islamic Society of North America.
  isna,
  karachi,
}

/// School of thought determining when Asr begins.
enum AsrMadhab {
  /// Asr begins when an object's shadow equals its own length.
  shafi,

  /// Asr begins when an object's shadow equals twice its own length.
  hanafi,
}

/// Fallback used where the sun never reaches the Fajr or Isha twilight angle,
/// which happens at high latitudes in summer.
enum HighLatitudeFallback {
  /// Fajr and Isha are clamped to the middle of the night.
  middleOfTheNight,

  /// Fajr and Isha are clamped to one seventh of the night.
  seventhOfTheNight,

  /// The night is divided in proportion to the configured twilight angles.
  twilightAngle,
}

/// Immutable configuration for a single schedule computation.
///
/// This object is passed per call; the engine never persists or caches it.
class PrayerSettings {
  const PrayerSettings({
    this.method = PrayerCalculationMethod.muslimWorldLeague,
    this.madhab = AsrMadhab.shafi,
    this.highLatitudeFallback = HighLatitudeFallback.middleOfTheNight,
  });

  final PrayerCalculationMethod method;
  final AsrMadhab madhab;
  final HighLatitudeFallback highLatitudeFallback;

  PrayerSettings copyWith({
    PrayerCalculationMethod? method,
    AsrMadhab? madhab,
    HighLatitudeFallback? highLatitudeFallback,
  }) {
    return PrayerSettings(
      method: method ?? this.method,
      madhab: madhab ?? this.madhab,
      highLatitudeFallback: highLatitudeFallback ?? this.highLatitudeFallback,
    );
  }
}
