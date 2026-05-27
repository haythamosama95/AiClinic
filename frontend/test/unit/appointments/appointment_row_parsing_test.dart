import 'package:ai_clinic/features/appointments/domain/appointment_row_parsing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseAppointmentDateTime', () {
    test('parses ISO-8601 strings', () {
      expect(parseAppointmentDateTime('2026-05-27T09:00:00.000Z'), DateTime.parse('2026-05-27T09:00:00.000Z'));
    });

    test('passes through DateTime values', () {
      final dt = DateTime.utc(2026, 5, 27, 9);
      expect(parseAppointmentDateTime(dt), same(dt));
    });

    test('returns null for null, empty, or invalid input', () {
      expect(parseAppointmentDateTime(null), isNull);
      expect(parseAppointmentDateTime(''), isNull);
      expect(parseAppointmentDateTime('   '), isNull);
      expect(parseAppointmentDateTime('not-a-date'), isNull);
    });

    test('stupid user: unexpected types coerced via toString', () {
      expect(parseAppointmentDateTime(12345), isNull);
    });
  });

  group('optionalAppointmentString', () {
    test('trims and returns non-empty strings', () {
      expect(optionalAppointmentString('  hello  '), 'hello');
    });

    test('returns null for blank values', () {
      expect(optionalAppointmentString(null), isNull);
      expect(optionalAppointmentString(''), isNull);
      expect(optionalAppointmentString('   '), isNull);
    });
  });

  group('optionalAppointmentInt', () {
    test('parses integer values', () {
      expect(optionalAppointmentInt(20), 20);
      expect(optionalAppointmentInt('15'), 15);
    });

    test('returns null for invalid numbers', () {
      expect(optionalAppointmentInt(null), isNull);
      expect(optionalAppointmentInt('abc'), isNull);
      expect(optionalAppointmentInt(''), isNull);
    });
  });
}
