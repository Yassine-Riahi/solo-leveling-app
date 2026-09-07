import 'dart:async';

import 'package:flutter/material.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../prayer/prayer.dart';
import 'clock.dart';
import 'day_location.dart';
import 'day_palette.dart';

/// Vertical pixels used to draw one minute of the day.
///
/// Window heights are a direct multiple of their real duration, so a longer
/// window is always visibly taller than a shorter one.
const double pixelsPerMinute = 1.1;

/// A day of prayer windows drawn as a proportional vertical timeline.
class DayView extends StatefulWidget {
  const DayView({
    super.key,
    this.clock = const SystemClock(),
    this.location = DayLocation.fallback,
    this.initialDate,
  });

  final Clock clock;
  final DayLocation location;

  /// Day shown on first build. Defaults to the clock's current day.
  final DateTime? initialDate;

  @override
  State<DayView> createState() => _DayViewState();
}

class _DayViewState extends State<DayView> {
  late DateTime _date;
  final ScrollController _scrollController = ScrollController();
  Timer? _ticker;
  PrayerName _centered = PrayerName.fajr;

  @override
  void initState() {
    super.initState();
    // Idempotent; the engine also does this lazily, but `_today()` needs the
    // database before the first schedule is computed.
    tz_data.initializeTimeZones();
    _date = widget.initialDate ?? _today();
    _scrollController.addListener(_updateCentered);
    _ticker = Timer.periodic(
      const Duration(seconds: 20),
      (_) => setState(() {}),
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  /// Today's calendar date *at the shown location*, not on the host machine.
  ///
  /// A user in another country still sees the location's current day, which is
  /// what the displayed times belong to.
  DateTime _today() {
    final tz.TZDateTime now = tz.TZDateTime.from(
      widget.clock.now(),
      tz.getLocation(widget.location.timeZone),
    );
    return DateTime(now.year, now.month, now.day);
  }

  bool get _isToday {
    final DateTime today = _today();
    return _date.year == today.year &&
        _date.month == today.month &&
        _date.day == today.day;
  }

  void _shiftDay(int days) {
    setState(() {
      _date = DateTime(_date.year, _date.month, _date.day + days);
      _centered = PrayerName.fajr;
    });
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
  }

  PrayerSchedule get _schedule => computePrayerSchedule(
        latitude: widget.location.latitude,
        longitude: widget.location.longitude,
        date: _date,
        timeZone: widget.location.timeZone,
      );

  /// The window containing the current instant, or null when the shown day is
  /// not today or the moment falls outside the drawn span.
  PrayerWindow? _activeWindow(PrayerSchedule schedule) {
    if (!_isToday) return null;
    final tz.TZDateTime now = tz.TZDateTime.from(
      widget.clock.now(),
      schedule.fajr.start.location,
    );
    for (final PrayerWindow window in schedule.windows) {
      if (window.contains(now)) return window;
    }
    return null;
  }

  void _updateCentered() {
    if (!_scrollController.hasClients) return;
    final PrayerSchedule schedule = _schedule;
    final tz.TZDateTime dayStart = schedule.fajr.start;
    final double centreOffset = _scrollController.offset +
        _scrollController.position.viewportDimension / 2;
    final double minutes = centreOffset / pixelsPerMinute;
    final tz.TZDateTime centreMoment =
        dayStart.add(Duration(minutes: minutes.round()));

    PrayerName found = schedule.windows.first.name;
    for (final PrayerWindow window in schedule.windows) {
      if (!centreMoment.isBefore(window.start)) found = window.name;
    }
    if (found != _centered) {
      setState(() => _centered = found);
    }
  }

  @override
  Widget build(BuildContext context) {
    final PrayerSchedule schedule = _schedule;
    final PrayerWindow? active = _activeWindow(schedule);
    final Color background =
        prayerBackgrounds[_centered] ?? prayerBackgrounds[PrayerName.fajr]!;
    final Color foreground = foregroundOn(background);

    return AnimatedContainer(
      key: const Key('background'),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(color: background),
      child: SafeArea(
        child: Column(
          children: <Widget>[
            _Header(
              date: _date,
              locationLabel: widget.location.label,
              foreground: foreground,
              active: active,
              now: _isToday ? widget.clock.now() : null,
              onPrevious: () => _shiftDay(-1),
              onNext: () => _shiftDay(1),
            ),
            Expanded(
              child: _Timeline(
                schedule: schedule,
                controller: _scrollController,
                foreground: foreground,
                active: active,
                now: _isToday ? widget.clock.now() : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.date,
    required this.locationLabel,
    required this.foreground,
    required this.active,
    required this.now,
    required this.onPrevious,
    required this.onNext,
  });

  final DateTime date;
  final String locationLabel;
  final Color foreground;
  final PrayerWindow? active;
  final DateTime? now;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Column(
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              IconButton(
                onPressed: onPrevious,
                color: foreground,
                icon: const Icon(Icons.chevron_left),
                tooltip: 'Previous day',
              ),
              Column(
                children: <Widget>[
                  Text(
                    _formatDate(date),
                    style: TextStyle(
                      color: foreground,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    locationLabel,
                    style: TextStyle(color: foreground, fontSize: 12),
                  ),
                ],
              ),
              IconButton(
                onPressed: onNext,
                color: foreground,
                icon: const Icon(Icons.chevron_right),
                tooltip: 'Next day',
              ),
            ],
          ),
          if (active != null && now != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _remainingLabel(active!, now!),
                key: const Key('countdown'),
                style: TextStyle(color: foreground, fontSize: 14),
              ),
            ),
        ],
      ),
    );
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline({
    required this.schedule,
    required this.controller,
    required this.foreground,
    required this.active,
    required this.now,
  });

  final PrayerSchedule schedule;
  final ScrollController controller;
  final Color foreground;
  final PrayerWindow? active;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final tz.TZDateTime dayStart = schedule.fajr.start;
    final tz.TZDateTime dayEnd = schedule.isha.end;
    final double totalHeight =
        dayEnd.difference(dayStart).inMinutes * pixelsPerMinute;

    double topFor(tz.TZDateTime moment) =>
        moment.difference(dayStart).inMinutes * pixelsPerMinute;

    final List<Widget> children = <Widget>[
      for (final PrayerWindow window in schedule.windows)
        Positioned(
          top: topFor(window.start),
          left: 0,
          right: 0,
          height: window.duration.inMinutes * pixelsPerMinute,
          child: _WindowTile(
            window: window,
            foreground: foreground,
            isActive: active?.name == window.name,
          ),
        ),
    ];

    if (now != null) {
      final tz.TZDateTime localNow =
          tz.TZDateTime.from(now!, dayStart.location);
      if (!localNow.isBefore(dayStart) && !localNow.isAfter(dayEnd)) {
        children.add(
          Positioned(
            top: topFor(localNow),
            left: 0,
            right: 0,
            child: _NowIndicator(foreground: foreground),
          ),
        );
      }
    }

    // Trailing space of half a viewport so the final window can still reach
    // the vertical centre; without it the last prayer's colour is unreachable
    // on tall screens.
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return SingleChildScrollView(
          controller: controller,
          child: Column(
            children: <Widget>[
              SizedBox(
                height: totalHeight,
                child: Stack(children: children),
              ),
              SizedBox(height: constraints.maxHeight / 2),
            ],
          ),
        );
      },
    );
  }
}

class _WindowTile extends StatelessWidget {
  const _WindowTile({
    required this.window,
    required this.foreground,
    required this.isActive,
  });

  final PrayerWindow window;
  final Color foreground;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: Key('window-${window.name.name}'),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: foreground.withOpacity(isActive ? 0.9 : 0.3),
          width: isActive ? 2.5 : 1,
        ),
        color: foreground.withOpacity(isActive ? 0.14 : 0.05),
      ),
      child: Align(
        alignment: Alignment.topLeft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              _prayerLabel(window.name),
              style: TextStyle(
                color: foreground,
                fontSize: 16,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            Text(
              '${_formatTime(window.start)} – ${_formatTime(window.end)}',
              style: TextStyle(color: foreground, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class _NowIndicator extends StatelessWidget {
  const _NowIndicator({required this.foreground});

  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Row(
      key: const Key('now-indicator'),
      children: <Widget>[
        Container(
          width: 10,
          height: 10,
          margin: const EdgeInsets.only(left: 6),
          decoration: BoxDecoration(
            color: foreground,
            shape: BoxShape.circle,
          ),
        ),
        Expanded(child: Container(height: 2, color: foreground)),
      ],
    );
  }
}

String _prayerLabel(PrayerName name) {
  switch (name) {
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

String _formatTime(DateTime time) =>
    '${time.hour.toString().padLeft(2, '0')}:'
    '${time.minute.toString().padLeft(2, '0')}';

String _formatDate(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

String _remainingLabel(PrayerWindow window, DateTime now) {
  final Duration left = window.end.difference(
    tz.TZDateTime.from(now, window.end.location),
  );
  if (left.isNegative) return '${_prayerLabel(window.name)} has ended';
  final int hours = left.inHours;
  final int minutes = left.inMinutes.remainder(60);
  final String amount = hours > 0 ? '${hours}h ${minutes}m' : '${minutes}m';
  return '$amount left in ${_prayerLabel(window.name)}';
}
