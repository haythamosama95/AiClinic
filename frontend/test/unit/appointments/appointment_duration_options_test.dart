import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/features/appointments/domain/appointment_duration_options.dart';

void main() {
  group('AppointmentDurationOptions', () {
    test('presetMinutes covers 15-minute steps through 3 hours', () {
      expect(AppointmentDurationOptions.defaultMinutes, 30);
      expect(AppointmentDurationOptions.presetMinutes, [15, 30, 45, 60, 75, 90, 105, 120, 135, 150, 165, 180]);
    });

    test('formatMinutes uses minutes below one hour and hr labels above', () {
      expect(AppointmentDurationOptions.formatMinutes(15), '15 minutes');
      expect(AppointmentDurationOptions.formatMinutes(45), '45 minutes');
      expect(AppointmentDurationOptions.formatMinutes(60), '1 hr');
      expect(AppointmentDurationOptions.formatMinutes(75), '1 hr 15 minutes');
      expect(AppointmentDurationOptions.formatMinutes(180), '3 hr');
    });

    test('selectItems includes an out-of-preset saved value', () {
      final items = AppointmentDurationOptions.selectItems(includeMinutes: 20);

      expect(items.values, contains(20));
      expect(items['20 minutes'], 20);
    });
  });
}
