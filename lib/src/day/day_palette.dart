import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../prayer/prayer.dart';

/// Sky colour for each prayer window.
///
/// The palette tracks the real sky across the day so that the background
/// carries information — which part of the day is on screen — rather than
/// merely decorating it.
const Map<PrayerName, Color> prayerBackgrounds = <PrayerName, Color>{
  PrayerName.fajr: Color(0xFF1A2456),
  PrayerName.dhuhr: Color(0xFF7EC8F0),
  PrayerName.asr: Color(0xFFF5C26B),
  PrayerName.maghrib: Color(0xFFE07A5F),
  PrayerName.isha: Color(0xFF12172E),
};

/// Foreground colours that stay legible on every value of
/// [prayerBackgrounds].
const Color lightForeground = Color(0xFFFFFFFF);
const Color darkForeground = Color(0xFF10131A);

/// WCAG 2.1 relative luminance of [color].
double relativeLuminance(Color color) {
  double channel(int value) {
    final double v = value / 255.0;
    return v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * channel(color.red) +
      0.7152 * channel(color.green) +
      0.0722 * channel(color.blue);
}

/// WCAG 2.1 contrast ratio between two colours, from 1.0 to 21.0.
double contrastRatio(Color a, Color b) {
  final double la = relativeLuminance(a);
  final double lb = relativeLuminance(b);
  final double lighter = la > lb ? la : lb;
  final double darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}

/// The foreground colour with the better contrast against [background].
Color foregroundOn(Color background) {
  return contrastRatio(lightForeground, background) >=
          contrastRatio(darkForeground, background)
      ? lightForeground
      : darkForeground;
}
