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
  });
}
