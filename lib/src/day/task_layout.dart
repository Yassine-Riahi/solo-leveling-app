import '../tasks/tasks.dart';

/// A task together with the horizontal slot it should occupy.
///
/// Overlapping tasks share the content width instead of covering each other:
/// [lane] is the column index and [laneCount] how many columns that cluster of
/// mutually overlapping tasks needs.
class LaidOutTask {
  const LaidOutTask({
    required this.task,
    required this.lane,
    required this.laneCount,
  });

  final Task task;
  final int lane;
  final int laneCount;
}

/// Assigns each task a column so that overlapping tasks sit side by side.
///
/// Tasks are grouped into clusters of mutual overlap; each cluster is packed
/// greedily into the fewest columns, so a task with no overlaps still gets the
/// full width.
List<LaidOutTask> layOutTasks(List<Task> tasks) {
  if (tasks.isEmpty) return const <LaidOutTask>[];

  final List<Task> ordered = List<Task>.of(tasks)
    ..sort((Task a, Task b) => a.start.compareTo(b.start));

  final List<LaidOutTask> result = <LaidOutTask>[];
  List<Task> cluster = <Task>[];
  DateTime? clusterEnd;

  void flush() {
    if (cluster.isEmpty) return;
    // Greedy packing: reuse the first column that has already finished.
    final List<DateTime> laneEnds = <DateTime>[];
    final List<int> lanes = <int>[];

    for (final Task task in cluster) {
      int lane = laneEnds.indexWhere((DateTime end) => !end.isAfter(task.start));
      if (lane == -1) {
        laneEnds.add(task.end);
        lane = laneEnds.length - 1;
      } else {
        laneEnds[lane] = task.end;
      }
      lanes.add(lane);
    }

    for (int i = 0; i < cluster.length; i++) {
      result.add(
        LaidOutTask(
          task: cluster[i],
          lane: lanes[i],
          laneCount: laneEnds.length,
        ),
      );
    }
    cluster = <Task>[];
    clusterEnd = null;
  }

  for (final Task task in ordered) {
    if (clusterEnd != null && !task.start.isBefore(clusterEnd!)) flush();
    cluster.add(task);
    clusterEnd = clusterEnd == null || task.end.isAfter(clusterEnd!)
        ? task.end
        : clusterEnd;
  }
  flush();

  return result;
}
