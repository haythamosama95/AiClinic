import 'package:ai_clinic/features/visits/domain/visit_row_parsing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseVisitDate', () {
    test('trivial: parses ISO date string to UTC midnight', () {
      final parsed = parseVisitDate('2026-05-31');
      expect(parsed, DateTime.utc(2026, 5, 31));
      expect(parsed!.isUtc, isTrue);
    });

    test('advanced: strips time component from full ISO datetime', () {
      final parsed = parseVisitDate('2026-05-31T15:30:00Z');
      expect(parsed, DateTime.utc(2026, 5, 31));
    });

    test('advanced: normalizes DateTime input to UTC date-only', () {
      final local = DateTime(2026, 5, 31, 18, 0);
      final parsed = parseVisitDate(local);
      expect(parsed, DateTime.utc(2026, 5, 31));
      expect(parsed!.isUtc, isTrue);
    });

    test('edge case: trims whitespace around date text', () {
      expect(parseVisitDate('  2026-05-31  '), DateTime.utc(2026, 5, 31));
    });

    test('edge case: returns null for null, empty, or invalid input', () {
      expect(parseVisitDate(null), isNull);
      expect(parseVisitDate(''), isNull);
      expect(parseVisitDate('   '), isNull);
      expect(parseVisitDate('not-a-date'), isNull);
    });

    test('invalid state: coerces non-string types via toString', () {
      expect(parseVisitDate(20260531), isNull);
    });
  });

  group('parseVisitDateTime', () {
    test('trivial: parses ISO datetime with Z suffix', () {
      final parsed = parseVisitDateTime('2026-05-31T09:00:00Z');
      expect(parsed, DateTime.utc(2026, 5, 31, 9));
      expect(parsed!.isUtc, isTrue);
    });

    test('advanced: preserves DateTime input unchanged', () {
      final original = DateTime.utc(2026, 5, 31, 12, 30);
      expect(parseVisitDateTime(original), same(original));
    });

    test('advanced: parses offset datetime', () {
      final parsed = parseVisitDateTime('2026-05-31T09:00:00+02:00');
      expect(parsed, isNotNull);
      expect(parsed!.hour, 7);
      expect(parsed.isUtc, isTrue);
    });

    test('edge case: returns null for null, empty, or invalid input', () {
      expect(parseVisitDateTime(null), isNull);
      expect(parseVisitDateTime(''), isNull);
      expect(parseVisitDateTime('bogus'), isNull);
    });
  });

  group('optionalVisitString', () {
    test('trivial: returns trimmed non-empty string', () {
      expect(optionalVisitString('  hello  '), 'hello');
    });

    test('edge case: returns null for null, empty, or whitespace-only', () {
      expect(optionalVisitString(null), isNull);
      expect(optionalVisitString(''), isNull);
      expect(optionalVisitString('   '), isNull);
    });

    test('advanced: coerces numeric values to string', () {
      expect(optionalVisitString(42), '42');
    });
  });

  group('optionalVisitInt', () {
    test('trivial: returns int values directly', () {
      expect(optionalVisitInt(123), 123);
    });

    test('advanced: truncates num to int', () {
      expect(optionalVisitInt(12.9), 12);
    });

    test('advanced: parses numeric strings with surrounding whitespace', () {
      expect(optionalVisitInt('  456  '), 456);
    });

    test('edge case: returns null for null, empty, or non-numeric strings', () {
      expect(optionalVisitInt(null), isNull);
      expect(optionalVisitInt(''), isNull);
      expect(optionalVisitInt('abc'), isNull);
      expect(optionalVisitInt('1,234'), isNull);
    });

    test('edge case: parses zero and negative values', () {
      expect(optionalVisitInt(0), 0);
      expect(optionalVisitInt('-5'), -5);
    });
  });

  group('parseVisitJsonObject', () {
    test('trivial: copies Map<String, dynamic> input', () {
      final input = {'key': 'value'};
      final parsed = parseVisitJsonObject(input);
      expect(parsed, {'key': 'value'});
      expect(identical(parsed, input), isFalse);
    });

    test('advanced: converts untyped Map to Map<String, dynamic>', () {
      final parsed = parseVisitJsonObject(<Object, Object>{'count': 1});
      expect(parsed, {'count': 1});
    });

    test('edge case: returns empty map for null or non-map values', () {
      expect(parseVisitJsonObject(null), isEmpty);
      expect(parseVisitJsonObject('not-a-map'), isEmpty);
      expect(parseVisitJsonObject(42), isEmpty);
    });
  });
}
