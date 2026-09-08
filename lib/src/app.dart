import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'day/day_view.dart';
import 'tasks/tasks.dart';

/// Root of the application.
///
/// Builds the persistent repository once, then hands it to the day view.
class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final Future<TaskRepository> _repository = _openRepository();

  Future<TaskRepository> _openRepository() async =>
      PrefsTaskRepository(await SharedPreferences.getInstance());

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Solo Leveling',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true),
      home: FutureBuilder<TaskRepository>(
        future: _repository,
        builder: (BuildContext context, AsyncSnapshot<TaskRepository> snap) {
          if (snap.hasError) {
            return Scaffold(
              body: Center(child: Text('Could not open storage: ${snap.error}')),
            );
          }
          if (!snap.hasData) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          return DayView(repository: snap.data!);
        },
      ),
    );
  }
}
