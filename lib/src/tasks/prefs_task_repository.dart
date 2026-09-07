import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

import 'in_memory_task_repository.dart';
import 'task.dart';
import 'task_repository.dart';

/// Persists tasks as a JSON document in `shared_preferences`.
///
/// Works on both android and web. Suited to the volumes here — one document
/// read and rewritten per change; a keyed store would be needed if task counts
/// grew by orders of magnitude.
class PrefsTaskRepository implements TaskRepository {
  PrefsTaskRepository(this._preferences);

  final SharedPreferences _preferences;

  static const String tasksKey = 'tasks.v1';
  static const String dismissedKey = 'tasks.dismissedPrayers.v1';

  List<Map<String, dynamic>> _readRaw() {
    final String? encoded = _preferences.getString(tasksKey);
    if (encoded == null || encoded.isEmpty) return <Map<String, dynamic>>[];
    final List<dynamic> decoded = jsonDecode(encoded) as List<dynamic>;
    return decoded.cast<Map<String, dynamic>>();
  }

  Future<void> _writeRaw(List<Map<String, dynamic>> raw) async {
    await _preferences.setString(tasksKey, jsonEncode(raw));
  }

  @override
  Future<List<Task>> tasksForDay(DateTime day, String timeZone) async {
    final tz.Location location = tz.getLocation(timeZone);
    final List<Task> all = _readRaw()
        .map((Map<String, dynamic> json) => Task.fromJson(json, location))
        .toList();
    return sortedTasksOn(all, day, location);
  }

  @override
  Future<void> save(Task task) async {
    final List<Map<String, dynamic>> raw = _readRaw()
      ..removeWhere((Map<String, dynamic> json) => json['id'] == task.id)
      ..add(task.toJson());
    await _writeRaw(raw);
  }

  @override
  Future<void> delete(String id) async {
    final List<Map<String, dynamic>> raw = _readRaw()
      ..removeWhere((Map<String, dynamic> json) => json['id'] == id);
    await _writeRaw(raw);
  }

  @override
  Future<Set<String>> dismissedPrayerIds() async =>
      (_preferences.getStringList(dismissedKey) ?? <String>[]).toSet();

  @override
  Future<void> dismissPrayer(String id) async {
    final Set<String> ids = await dismissedPrayerIds()..add(id);
    await _preferences.setStringList(dismissedKey, ids.toList());
  }

  @override
  Future<void> restorePrayer(String id) async {
    final Set<String> ids = await dismissedPrayerIds()..remove(id);
    await _preferences.setStringList(dismissedKey, ids.toList());
  }
}
