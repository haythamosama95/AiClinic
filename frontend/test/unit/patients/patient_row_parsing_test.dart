import 'package:ai_clinic/features/patients/domain/patient_row_parsing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parsePatientDate', () {
    test('parses ISO date strings to date-only DateTime', () {
      expect(parsePatientDate('2001-12-31'), DateTime.utc(2001, 12, 31));
    });

    test('returns null for null, empty, or invalid input', () {
      expect(parsePatientDate(null), isNull);
      expect(parsePatientDate(''), isNull);
      expect(parsePatientDate('   '), isNull);
      expect(parsePatientDate('31-12-2001'), isNull);
    });

    test('strips time component from DateTime values', () {
      expect(parsePatientDate(DateTime(2020, 6, 15, 23, 59)), DateTime.utc(2020, 6, 15));
    });
  });

  group('parsePatientDateTime', () {
    test('preserves full timestamp for audit fields', () {
      final parsed = parsePatientDateTime('2026-05-23T14:22:33.456Z');
      expect(parsed, DateTime.parse('2026-05-23T14:22:33.456Z'));
    });

    test('returns null for invalid timestamps', () {
      expect(parsePatientDateTime('not-a-timestamp'), isNull);
    });
  });

  group('optionalPatientString', () {
    test('trims and returns null for blank strings', () {
      expect(optionalPatientString('  hello '), 'hello');
      expect(optionalPatientString(''), isNull);
      expect(optionalPatientString(null), isNull);
    });
  });
}
