import 'dart:ui';

import 'package:ai_clinic/features/appointments/domain/appointment_calendar_status_style.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppointmentCalendarStatusPalette', () {
    test('advanced: styleFor returns non-null style for every status in light and dark', () {
      for (final brightness in Brightness.values) {
        for (final status in AppointmentStatus.values) {
          final style = AppointmentCalendarStatusPalette.styleFor(status, brightness);
          expect(style, isNotNull);
        }
      }
    });

    test('advanced: styleFor is deterministic across repeated calls', () {
      for (final brightness in [Brightness.light, Brightness.dark]) {
        for (final status in AppointmentStatus.values) {
          final first = AppointmentCalendarStatusPalette.styleFor(status, brightness);
          final second = AppointmentCalendarStatusPalette.styleFor(status, brightness);
          expect(identical(first, second), isTrue);
        }
      }
    });

    test('trivial: filteredOutStyle is non-null for both brightnesses', () {
      expect(AppointmentCalendarStatusPalette.filteredOutStyle(Brightness.light), isNotNull);
      expect(AppointmentCalendarStatusPalette.filteredOutStyle(Brightness.dark), isNotNull);
    });

    test('advanced: light and dark themes resolve to different style instances', () {
      for (final status in AppointmentStatus.values) {
        final light = AppointmentCalendarStatusPalette.styleFor(status, Brightness.light);
        final dark = AppointmentCalendarStatusPalette.styleFor(status, Brightness.dark);
        expect(identical(light, dark), isFalse);
      }

      final filteredLight = AppointmentCalendarStatusPalette.filteredOutStyle(Brightness.light);
      final filteredDark = AppointmentCalendarStatusPalette.filteredOutStyle(Brightness.dark);
      expect(identical(filteredLight, filteredDark), isFalse);
    });
  });
}
