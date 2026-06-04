import 'package:ai_clinic/features/appointments/domain/appointment_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppointmentSettings.fromRpcData', () {
    test('trivial: parses valid settings payload', () {
      final settings = AppointmentSettings.fromRpcData({
        'default_duration_minutes': 30,
        'min_duration_minutes': 5,
        'max_duration_minutes': 240,
      });

      expect(settings?.defaultDurationMinutes, 30);
      expect(settings?.minDurationMinutes, 5);
      expect(settings?.maxDurationMinutes, 240);
    });

    test('edge case: returns null when fields missing', () {
      expect(AppointmentSettings.fromRpcData({'default_duration_minutes': 20}), isNull);
    });

    test('regression: accepts numeric strings', () {
      final settings = AppointmentSettings.fromRpcData({
        'default_duration_minutes': '45',
        'min_duration_minutes': '5',
        'max_duration_minutes': '240',
      });

      expect(settings?.defaultDurationMinutes, 45);
    });

    test('parses working_schedule from settings payload', () {
      final settings = AppointmentSettings.fromRpcData({
        'default_duration_minutes': 20,
        'min_duration_minutes': 5,
        'max_duration_minutes': 240,
        'working_schedule': {
          'days': [
            {'day': 'monday', 'is_working_day': true, 'open_time': '09:00', 'close_time': '17:00'},
          ],
        },
      });

      expect(settings?.workingSchedule, isNotNull);
      expect(settings!.workingSchedule!.days.first.openTime, '09:00');
    });
  });
}
