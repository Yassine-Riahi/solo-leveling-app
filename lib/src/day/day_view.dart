import 'dart:async';

import 'package:flutter/material.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../prayer/prayer.dart';
import '../tasks/tasks.dart';
import 'clock.dart';
import 'day_location.dart';
import 'day_palette.dart';
import 'task_layout.dart';

/// Width of the left gutter carrying the hour labels.
const double gutterWidth = 48;

/// Vertical pixels used to draw one minute of the day.
///
/// Block heights are a direct multiple of their real duration, so a longer
/// task is always visibly taller than a shorter one.
const double pixelsPerMinute = 1.1;

/// A day of tasks drawn as a proportional vertical timeline.
class DayView extends StatefulWidget {
  const DayView({
    super.key,
    required this.repository,
    this.clock = const SystemClock(),
    this.location = DayLocation.fallback,
    this.initialDate,
  });

  /// Source of the day's tasks. Injected so tests can supply an in-memory
  /// implementation.
  final TaskRepository repository;

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
  List<LaidOutTask> _tasks = const <LaidOutTask>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    // Idempotent; `_today()` needs the database before any task is read.
    tz_data.initializeTimeZones();
    _date = widget.initialDate ?? _today();
    _scrollController.addListener(_updateCentered);
    _ticker = Timer.periodic(
      const Duration(seconds: 20),
      (_) => setState(() {}),
    );
    unawaited(_load());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  /// Seeds the day's prayers, then reads everything stored for it.
  Future<void> _load() async {
    setState(() => _loading = true);
    await seedPrayerTasks(
      repository: widget.repository,
      day: _date,
      latitude: widget.location.latitude,
      longitude: widget.location.longitude,
      timeZone: widget.location.timeZone,
    );
    final List<Task> tasks = await widget.repository.tasksForDay(
      _date,
      widget.location.timeZone,
    );
    if (!mounted) return;
    setState(() {
      _tasks = layOutTasks(tasks);
      _loading = false;
    });
  }

  /// Today's calendar date *at the shown location*, not on the host machine.
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
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
    unawaited(_load());
  }

  /// Start of the drawn span: the hour at or before the first task.
  tz.TZDateTime? get _dayStart {
    if (_tasks.isEmpty) return null;
    tz.TZDateTime earliest = _tasks.first.task.start;
    for (final LaidOutTask entry in _tasks) {
      if (entry.task.start.isBefore(earliest)) earliest = entry.task.start;
    }
    return _floorToHour(earliest);
  }

  /// End of the drawn span: the hour at or after the last task.
  tz.TZDateTime? get _dayEnd {
    if (_tasks.isEmpty) return null;
    tz.TZDateTime latest = _tasks.first.task.end;
    for (final LaidOutTask entry in _tasks) {
      if (entry.task.end.isAfter(latest)) latest = entry.task.end;
    }
    return _ceilToHour(latest);
  }

  /// The prayer task containing the current instant, or null when the shown
  /// day is not today.
  Task? _activeTask() {
    if (!_isToday || _tasks.isEmpty) return null;
    final tz.TZDateTime now = tz.TZDateTime.from(
      widget.clock.now(),
      _tasks.first.task.start.location,
    );
    for (final LaidOutTask entry in _tasks) {
      final Task task = entry.task;
      if (!now.isBefore(task.start) && !now.isAfter(task.end)) return task;
    }
    return null;
  }

  void _updateCentered() {
    if (!_scrollController.hasClients) return;
    final tz.TZDateTime? dayStart = _dayStart;
    if (dayStart == null) return;

    final double centreOffset = _scrollController.offset +
        _scrollController.position.viewportDimension / 2;
    final double minutes = centreOffset / pixelsPerMinute;
    final tz.TZDateTime centreMoment =
        dayStart.add(Duration(minutes: minutes.round()));

    PrayerName? found;
    for (final LaidOutTask entry in _tasks) {
      final PrayerName? name = prayerNameOf(entry.task);
      if (name == null) continue;
      if (!centreMoment.isBefore(entry.task.start)) found = name;
    }
    if (found != null && found != _centered) {
      setState(() => _centered = found!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Task? active = _activeTask();
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
              child: _loading
                  ? Center(
                      child: CircularProgressIndicator(color: foreground),
                    )
                  : _Timeline(
                      tasks: _tasks,
                      dayStart: _dayStart,
                      dayEnd: _dayEnd,
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
  final Task? active;
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
    required this.tasks,
    required this.dayStart,
    required this.dayEnd,
    required this.controller,
    required this.foreground,
    required this.active,
    required this.now,
  });

  final List<LaidOutTask> tasks;
  final tz.TZDateTime? dayStart;
  final tz.TZDateTime? dayEnd;
  final ScrollController controller;
  final Color foreground;
  final Task? active;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final tz.TZDateTime? start = dayStart;
    final tz.TZDateTime? end = dayEnd;
    if (start == null || end == null) {
      return Center(
        child: Text(
          'Nothing scheduled',
          key: const Key('empty-day'),
          style: TextStyle(color: foreground),
        ),
      );
    }

    final double totalHeight =
        end.difference(start).inMinutes * pixelsPerMinute;
    double topFor(tz.TZDateTime moment) =>
        moment.difference(start).inMinutes * pixelsPerMinute;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double contentWidth = constraints.maxWidth - gutterWidth - 12;

        final List<Widget> children = <Widget>[
          for (final tz.TZDateTime hour in _hoursBetween(start, end))
            Positioned(
              top: topFor(hour),
              left: 0,
              right: 0,
              child: _HourRow(
                label: '${hour.hour.toString().padLeft(2, '0')}:00',
                foreground: foreground,
              ),
            ),
          for (final LaidOutTask entry in tasks)
            Positioned(
              top: topFor(entry.task.start),
              left: gutterWidth +
                  (contentWidth / entry.laneCount) * entry.lane,
              width: contentWidth / entry.laneCount,
              height: entry.task.duration.inMinutes * pixelsPerMinute,
              child: _TaskTile(
                task: entry.task,
                foreground: foreground,
                isActive: active?.id == entry.task.id,
              ),
            ),
        ];

        if (now != null) {
          final tz.TZDateTime localNow =
              tz.TZDateTime.from(now!, start.location);
          if (!localNow.isBefore(start) && !localNow.isAfter(end)) {
            children.add(
              Positioned(
                top: topFor(localNow),
                left: gutterWidth - 6,
                right: 0,
                child: _NowIndicator(foreground: foreground),
              ),
            );
          }
        }

        // Trailing space of half a viewport so the final block can still reach
        // the vertical centre.
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

class _TaskTile extends StatelessWidget {
  const _TaskTile({
    required this.task,
    required this.foreground,
    required this.isActive,
  });

  final Task task;
  final Color foreground;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final bool done = task.isDone;

    return Container(
      key: Key('task-${task.id}'),
      margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        // Prayer tasks carry a solid border; ordinary tasks a dashed-looking
        // lighter one, plus a leading accent bar.
        border: Border.all(
          color: foreground.withOpacity(isActive ? 0.9 : 0.3),
          width: isActive ? 2.5 : 1,
        ),
        color: foreground.withOpacity(
          done ? 0.03 : (task.isPrayer ? (isActive ? 0.14 : 0.08) : 0.02),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (task.isPrayer)
            Padding(
              padding: const EdgeInsets.only(right: 8, top: 2),
              child: Icon(
                Icons.brightness_2_outlined,
                key: Key('prayer-mark-${task.id}'),
                size: 14,
                color: foreground.withOpacity(0.8),
              ),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  task.title,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foreground.withOpacity(done ? 0.6 : 1),
                    fontSize: 15,
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                    decoration:
                        done ? TextDecoration.lineThrough : TextDecoration.none,
                    decorationColor: foreground,
                  ),
                ),
                Text(
                  '${_formatTime(task.start)} – ${_formatTime(task.end)}',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foreground.withOpacity(done ? 0.5 : 0.85),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (done)
            Icon(
              Icons.check,
              key: Key('done-${task.id}'),
              size: 16,
              color: foreground.withOpacity(0.7),
            ),
        ],
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

/// One hour boundary: a label in the gutter and a rule across the content.
class _HourRow extends StatelessWidget {
  const _HourRow({required this.label, required this.foreground});

  final String label;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        SizedBox(
          width: gutterWidth,
          child: Text(
            label,
            textAlign: TextAlign.right,
            style: TextStyle(
              color: foreground.withOpacity(0.65),
              fontSize: 11,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Container(height: 1, color: foreground.withOpacity(0.18)),
        ),
      ],
    );
  }
}

/// The prayer a seeded task represents, or null for an ordinary task.
PrayerName? prayerNameOf(Task task) {
  if (!task.isPrayer) return null;
  final List<String> parts = task.id.split(':');
  if (parts.length != 3) return null;
  for (final PrayerName name in PrayerName.values) {
    if (name.name == parts.last) return name;
  }
  return null;
}

/// Every whole hour in `[start, end]`, inclusive of both ends.
List<tz.TZDateTime> _hoursBetween(tz.TZDateTime start, tz.TZDateTime end) {
  final List<tz.TZDateTime> hours = <tz.TZDateTime>[];
  tz.TZDateTime cursor = start;
  while (!cursor.isAfter(end)) {
    hours.add(cursor);
    cursor = cursor.add(const Duration(hours: 1));
  }
  return hours;
}

tz.TZDateTime _floorToHour(tz.TZDateTime moment) => tz.TZDateTime(
      moment.location,
      moment.year,
      moment.month,
      moment.day,
      moment.hour,
    );

tz.TZDateTime _ceilToHour(tz.TZDateTime moment) {
  final tz.TZDateTime floored = _floorToHour(moment);
  return floored == moment ? floored : floored.add(const Duration(hours: 1));
}

String _formatTime(DateTime time) =>
    '${time.hour.toString().padLeft(2, '0')}:'
    '${time.minute.toString().padLeft(2, '0')}';

String _formatDate(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

String _remainingLabel(Task task, DateTime now) {
  final Duration left =
      task.end.difference(tz.TZDateTime.from(now, task.end.location));
  if (left.isNegative) return '${task.title} has ended';
  final int hours = left.inHours;
  final int minutes = left.inMinutes.remainder(60);
  final String amount = hours > 0 ? '${hours}h ${minutes}m' : '${minutes}m';
  return '$amount left in ${task.title}';
}
