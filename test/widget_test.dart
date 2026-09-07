import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solo_leveling_app/src/app.dart';

void main() {
  testWidgets('app boots into the day view backed by storage',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    // The day view names its prayers; the old counter demo did not.
    expect(find.text('Fajr'), findsOneWidget);
    expect(find.text('Isha'), findsOneWidget);
    expect(find.text('Tunis'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('tasks seeded on first open survive a restart',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();
    expect(find.text('Fajr'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());

    // Same mock store, fresh widget tree: seeding must not duplicate.
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();
    expect(find.text('Fajr'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
