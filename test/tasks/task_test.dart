import 'package:flutter_test/flutter_test.dart';
import 'package:solo_leveling_app/src/tasks/tasks.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

void main() {
  // Must run before any getLocation call in the enclosing body.
  tz_data.initializeTimeZones();
  final tz.Location tunis = tz.getLocation('Africa/Tunis');

  Task sample() => Task(
        id: 'task-1',
        title: 'Read Qur\'an',
        start: tz.TZDateTime(tunis, 2024, 6, 1, 9, 30),
        end: tz.TZDateTime(tunis, 2024, 6, 1, 10),
        isDone: true,
        notes: 'Surah al-Kahf',
        priority: TaskPriority.high,
        list: 'Spiritual',
        isPrayer: false,
      );

  group('Task', () {
    test('round-trips through JSON without losing a field', () {
      final Task original = sample();
      final Task restored = Task.fromJson(original.toJson(), tunis);

      expect(restored, original);
      expect(restored.id, original.id);
      expect(restored.title, original.title);
      expect(restored.start, original.start);
      expect(restored.end, original.end);
      expect(restored.isDone, isTrue);
      expect(restored.notes, 'Surah al-Kahf');
      expect(restored.priority, TaskPriority.high);
      expect(restored.list, 'Spiritual');
      expect(restored.isPrayer, isFalse);
    });

    test('serialises times as UTC and restores them in the given zone', () {
      final Map<String, dynamic> json = sample().toJson();

      expect(json['start'], endsWith('Z'));
      expect(json['end'], endsWith('Z'));
      // 09:30 in Tunis (UTC+1) is 08:30 UTC.
      expect(json['start'], '2024-06-01T08:30:00.000Z');

      final Task restored = Task.fromJson(json, tunis);
      expect(restored.start.hour, 9);
      expect(restored.start.location.name, 'Africa/Tunis');
    });

    test('restores into whichever zone is asked for', () {
      final tz.Location tokyo = tz.getLocation('Asia/Tokyo');
      final Task restored = Task.fromJson(sample().toJson(), tokyo);

      // Same instant, different wall clock.
      expect(restored.start.isAtSameMomentAs(sample().start), isTrue);
      expect(restored.start.location.name, 'Asia/Tokyo');
    });

    test('copyWith changes only what it is given', () {
      final Task original = sample();
      final Task renamed = original.copyWith(title: 'Tafsir');

      expect(renamed.title, 'Tafsir');
      expect(renamed.id, original.id);
      expect(renamed.notes, original.notes);
      expect(renamed.priority, original.priority);
      expect(renamed.isDone, original.isDone);
    });

    test('copyWith can clear nullable fields explicitly', () {
      final Task cleared =
          sample().copyWith(clearNotes: true, clearList: true);

      expect(cleared.notes, isNull);
      expect(cleared.list, isNull);
      expect(cleared.title, sample().title);
    });

    test('duration reflects the interval', () {
      expect(sample().duration, const Duration(minutes: 30));
    });
  });
}
