import 'package:ai_clinic/features/ai/billing/billing_money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('R3-M6 BillingMoney', () {
    test('formats EGP minor units as two-decimal major units', () {
      expect(BillingMoney.format(10000, 'EGP', 'en'), contains('100.00'));
      expect(BillingMoney.format(1, 'EGP', 'en'), contains('0.01'));
    });
  });
}
