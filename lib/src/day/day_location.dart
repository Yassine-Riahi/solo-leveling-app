/// Fixed location used until a geolocation feature replaces it.
///
/// TEMPORARY: SOL-3 deliberately excludes device geolocation, so the day view
/// is pinned to one city. A later issue should replace every use of this with
/// a real, user-supplied location.
class DayLocation {
  const DayLocation({
    required this.latitude,
    required this.longitude,
    required this.timeZone,
    required this.label,
  });

  final double latitude;
  final double longitude;
  final String timeZone;
  final String label;

  static const DayLocation fallback = DayLocation(
    latitude: 36.8065,
    longitude: 10.1815,
    timeZone: 'Africa/Tunis',
    label: 'Tunis',
  );
}
