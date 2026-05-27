import 'package:ai_clinic/features/appointments/domain/appointment_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppointmentType.tryParse', () {
    test('parses known enum wire values', () {
      expect(AppointmentType.tryParse('planned'), AppointmentType.planned);
      expect(AppointmentType.tryParse('walk_in'), AppointmentType.walkIn);
    });

    test('is case-insensitive and trims whitespace', () {
      expect(AppointmentType.tryParse('  PLANNED '), AppointmentType.planned);
      expect(AppointmentType.tryParse('\tWALK_IN\n'), AppointmentType.walkIn);
    });

    test('returns null for empty or unrecognized values', () {
      expect(AppointmentType.tryParse(null), isNull);
      expect(AppointmentType.tryParse(''), isNull);
      expect(AppointmentType.tryParse('   '), isNull);
      expect(AppointmentType.tryParse('walkin'), isNull);
      expect(AppointmentType.tryParse('walk-in'), isNull);
    });

    test('stupid user input does not throw', () {
      expect(() => AppointmentType.tryParse('null'), returnsNormally);
      expect(AppointmentType.tryParse('null'), isNull);
      expect(AppointmentType.tryParse('undefined'), isNull);
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
    test('provides human-readable labels', () {
      expect(AppointmentType.planned.label, 'Planned');
      expect(AppointmentType.walkIn.label, 'Walk-in');
    });
  });
}
