import 'package:ai_clinic/features/patients/domain/patient_row_parsing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatPatientDateWire', () {
    test('serializes calendar components without timezone shift', () {
      expect(formatPatientDateWire(DateTime(1990, 5, 15, 23, 30)), '1990-05-15');
      expect(formatPatientDateWire(DateTime.utc(1990, 5, 15)), '1990-05-15');
    });
  });

  group('normalizePatientDate', () {
    test('normalizes to UTC midnight preserving calendar day', () {
      expect(normalizePatientDate(DateTime(1990, 5, 15, 23, 30)), DateTime.utc(1990, 5, 15));
    });
  });

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

    test('advanced: returns same instant when given DateTime', () {
      final instant = DateTime.utc(2026, 5, 23, 14, 22, 33, 456);
      expect(parsePatientDateTime(instant), instant);
    });

    test('edge case: returns null for null input', () {
      expect(parsePatientDateTime(null), isNull);
    });

    test('edge case: returns null for empty or whitespace string', () {
      expect(parsePatientDateTime(''), isNull);
      expect(parsePatientDateTime('   '), isNull);
    });

    test('edge case: returns null for unparseable string', () {
      expect(parsePatientDateTime('31-12-2026'), isNull);
    });
  });

  group('parsePatientMrn', () {
    test('trivial: prefers mrn key over patient_mrn', () {
      expect(
        parsePatientMrn({'mrn': 'MRN-000001', 'patient_mrn': 'MRN-000099'}),
        'MRN-000001',
      );
    });

    test('trivial: falls back to patient_mrn when mrn absent', () {
      expect(parsePatientMrn({'patient_mrn': 'MRN-000042'}), 'MRN-000042');
    });

    test('edge case: returns null when both keys missing', () {
      expect(parsePatientMrn({}), isNull);
    });

    test('edge case: returns null for blank or whitespace values', () {
      expect(parsePatientMrn({'mrn': ''}), isNull);
      expect(parsePatientMrn({'mrn': '   '}), isNull);
      expect(parsePatientMrn({'patient_mrn': '  '}), isNull);
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
