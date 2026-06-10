import 'package:ai_clinic/features/setup/domain/staff_password_validation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StaffPasswordValidation.validateInitialPassword', () {
    test('accepts passwords that meet backend complexity rules', () {
      expect(StaffPasswordValidation.validateInitialPassword('Secret12'), isNull);
      expect(StaffPasswordValidation.validateInitialPassword('abcdefgh'), isNull);
    });

    test('rejects empty and short passwords', () {
      expect(StaffPasswordValidation.validateInitialPassword(''), isNotNull);
      expect(StaffPasswordValidation.validateInitialPassword('short'), contains('8 characters'));
    });

    test('rejects passwords without letters', () {
      expect(StaffPasswordValidation.validateInitialPassword('12345678'), contains('letter'));
    });
  });
}
