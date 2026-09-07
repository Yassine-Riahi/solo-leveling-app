import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solo_leveling_app/src/app.dart';

void main() {
  testWidgets('app boots into the day view', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump();

    // The day view names its prayers; the old counter demo did not.
    expect(find.text('Fajr'), findsOneWidget);
    expect(find.text('Isha'), findsOneWidget);
    expect(find.text('Tunis'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
