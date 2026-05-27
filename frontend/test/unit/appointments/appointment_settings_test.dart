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
  });
}
