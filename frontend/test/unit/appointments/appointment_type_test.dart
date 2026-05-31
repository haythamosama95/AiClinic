import 'package:ai_clinic/features/appointments/domain/appointment_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppointmentType.tryParse', () {
    test('parses planned', () {
      expect(AppointmentType.tryParse('planned'), AppointmentType.planned);
    });

    test('is case-insensitive and trims whitespace', () {
      expect(AppointmentType.tryParse('  PLANNED '), AppointmentType.planned);
    });

    test('returns null for empty or unrecognized values', () {
      expect(AppointmentType.tryParse(null), isNull);
      expect(AppointmentType.tryParse(''), isNull);
      expect(AppointmentType.tryParse('invalid'), isNull);
    });
  });

  group('AppointmentType.wireValue', () {
    test('round-trips with tryParse', () {
      for (final type in AppointmentType.values) {
        expect(AppointmentType.tryParse(type.wireValue), type);
      }
    });
  });

  group('AppointmentType.label', () {
    test('provides human-readable label', () {
      expect(AppointmentType.planned.label, 'Planned');
    });
  });
}
