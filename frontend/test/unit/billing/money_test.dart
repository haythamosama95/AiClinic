import 'package:ai_clinic/features/billing/domain/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Money', () {
    test('parse normalizes wire values to two decimal places', () {
      expect(Money.parse('100').wireValue, '100.00');
      expect(Money.parse('100.5').wireValue, '100.50');
    });

    test('parse rejects comma decimal separators', () {
      expect(() => Money.parse('1,50'), throwsFormatException);
    });

    test('parse rejects comma decimal separators with exact message', () {
      expect(
        () => Money.parse('1,50'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            'Money values must use a dot decimal separator: 1,50',
          ),
        ),
      );
    });

    test('tryParse returns null for malformed values', () {
      expect(Money.tryParse('not-a-number'), isNull);
    });

    test('fromRow-style rejection via tryParse on domain models', () {
      expect(Money.tryParse('12.34'), isNotNull);
      expect(Money.tryParse(''), equals(Money.zero));
    });

    test('arithmetic helpers preserve scale', () {
      final left = Money.parse('10.00');
      final right = Money.parse('2.50');
      expect((left - right).wireValue, '7.50');
    });

    test('zero constant and isZero', () {
      expect(Money.zero.isZero, isTrue);
      expect(Money.parse('0').isZero, isTrue);
      expect(Money.parse('0.00').isZero, isTrue);
      expect(Money.parse('1.00').isZero, isFalse);
    });

    test('fromWire returns zero for null and bad values', () {
      expect(Money.fromWire(null), Money.zero);
      expect(Money.fromWire('bad'), Money.zero);
      expect(Money.fromWire('bad').isZero, isTrue);
    });

    test('parse on whitespace-only returns zero', () {
      expect(Money.parse('   '), Money.zero);
      expect(Money.parse('\t\n'), Money.zero);
    });

    test('isPositive and isNegative', () {
      final positive = Money.parse('1.00');
      final negative = Money.parse('-1.00');
      final zero = Money.zero;

      expect(positive.isPositive, isTrue);
      expect(positive.isNegative, isFalse);
      expect(negative.isPositive, isFalse);
      expect(negative.isNegative, isTrue);
      expect(zero.isPositive, isFalse);
      expect(zero.isNegative, isFalse);
    });

    test('compareTo orders values', () {
      final low = Money.parse('1.00');
      final high = Money.parse('2.00');
      final same = Money.parse('1.00');

      expect(low.compareTo(high), lessThan(0));
      expect(high.compareTo(low), greaterThan(0));
      expect(low.compareTo(same), 0);
    });

    test('value equality and hashCode', () {
      final a = Money.parse('12.34');
      final b = Money.parse('12.34');
      final c = Money.parse('12.35');

      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(c)));
    });

    test('asDouble returns numeric value', () {
      expect(Money.parse('12.34').asDouble, 12.34);
      expect(Money.parse('-5.50').asDouble, -5.50);
    });

    test('toString equals wireValue', () {
      final money = Money.parse('99.99');
      expect(money.toString(), money.wireValue);
      expect(money.toString(), '99.99');
    });

    test('wireValue rounds at two-decimal boundaries', () {
      expect(Money.parse('1.005').wireValue, '1.01');
      expect(Money.parse('1.004').wireValue, '1.00');
      expect(Money.parse('1.999').wireValue, '2.00');
    });

    test('parse retains precision until wireValue', () {
      final sum = Money.parse('10.00') + Money.parse('0.001');
      expect(sum.wireValue, '10.00');
      expect(sum.asDouble, closeTo(10.001, 0.0001));
    });

    test('parse rejects letters with FormatException', () {
      expect(
        () => Money.parse('abc'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            'Invalid money value: abc',
          ),
        ),
      );
    });

    test('parse rejects multiple dots with FormatException', () {
      expect(
        () => Money.parse('1.2.3'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            'Invalid money value: 1.2.3',
          ),
        ),
      );
    });
  });
}
