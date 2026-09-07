import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solo_leveling_app/src/day/day_palette.dart';
import 'package:solo_leveling_app/src/prayer/prayer.dart';

void main() {
  group('palette', () {
    test('defines a background for every prayer', () {
      for (final PrayerName name in PrayerName.values) {
        expect(prayerBackgrounds[name], isNotNull, reason: name.name);
      }
    });

    test('the chosen foreground clears 4.5:1 on every background', () {
      for (final MapEntry<PrayerName, Color> entry
          in prayerBackgrounds.entries) {
        final Color foreground = foregroundOn(entry.value);
        final double ratio = contrastRatio(foreground, entry.value);
        expect(
          ratio >= 4.5,
          isTrue,
          reason: '${entry.key.name}: contrast is '
              '${ratio.toStringAsFixed(2)}:1',
        );
      }
    });

    test('contrast ratio is symmetric and bounded', () {
      expect(contrastRatio(Colors.white, Colors.black), closeTo(21, 0.01));
      expect(contrastRatio(Colors.black, Colors.white), closeTo(21, 0.01));
      expect(contrastRatio(Colors.white, Colors.white), closeTo(1, 0.001));
    });
  });
}
