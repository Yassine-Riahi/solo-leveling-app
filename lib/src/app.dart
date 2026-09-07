import 'package:flutter/material.dart';

import 'day/day_view.dart';

/// Root of the application.
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Solo Leveling',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true),
      home: const DayView(),
    );
  }
}
