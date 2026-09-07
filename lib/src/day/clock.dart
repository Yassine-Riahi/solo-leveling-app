/// Source of the current instant.
///
/// Injected so that widgets depending on "now" can be pinned to a fixed
/// moment in tests; see [FixedClock].
abstract class Clock {
  const Clock();

  DateTime now();
}

/// Reads the real system clock.
class SystemClock extends Clock {
  const SystemClock();

  @override
  DateTime now() => DateTime.now();
}

/// Always reports [instant]. Test-only in practice.
class FixedClock extends Clock {
  const FixedClock(this.instant);

  final DateTime instant;

  @override
  DateTime now() => instant;
}
