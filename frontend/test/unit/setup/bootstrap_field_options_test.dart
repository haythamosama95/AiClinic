import 'package:ai_clinic/features/setup/domain/bootstrap_field_options.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BootstrapCurrencyOptions', () {
    test('defaultCode is EGP', () {
      expect(BootstrapCurrencyOptions.defaultCode, 'EGP');
    });

    test('isValid accepts lowercase currency codes', () {
      expect(BootstrapCurrencyOptions.isValid('egp'), isTrue);
      expect(BootstrapCurrencyOptions.isValid('EGP'), isTrue);
    });

    test('isValid rejects unknown codes', () {
      expect(BootstrapCurrencyOptions.isValid('NOTREAL'), isFalse);
    });

    test('filter returns matching subset', () {
      expect(BootstrapCurrencyOptions.filter('EG'), contains('EGP'));
    });
  });

  group('BootstrapTimezoneOptions', () {
    test('defaultZone is Africa/Cairo', () {
      expect(BootstrapTimezoneOptions.defaultZone, 'Africa/Cairo');
    });

    test('isValid accepts case-insensitive zones', () {
      expect(BootstrapTimezoneOptions.isValid('africa/cairo'), isTrue);
      expect(BootstrapTimezoneOptions.isValid('Africa/Cairo'), isTrue);
    });

    test('filter returns matching subset', () {
      expect(BootstrapTimezoneOptions.filter('cairo'), contains('Africa/Cairo'));
    });
  });
}
