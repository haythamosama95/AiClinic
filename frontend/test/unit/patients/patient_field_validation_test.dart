import 'package:ai_clinic/features/patients/domain/patient_field_validation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PatientFieldValidation', () {
    test('M5: rejects non-numeric mobile numbers', () {
      expect(PatientFieldValidation.validateMobileNumber('20100abc1234'), 'Only numbers are allowed.');
      expect(PatientFieldValidation.validateMobileNumber('20 100 555 1234'), 'Only numbers are allowed.');
    });

    test('accepts valid digit-only mobile numbers', () {
      expect(PatientFieldValidation.validateMobileNumber('201005551234'), isNull);
    });

    test('invalid state: null, empty, and whitespace-only are required', () {
      expect(PatientFieldValidation.validateMobileNumber(null), 'Mobile number is required.');
      expect(PatientFieldValidation.validateMobileNumber(''), 'Mobile number is required.');
      expect(PatientFieldValidation.validateMobileNumber('   '), 'Mobile number is required.');
    });

    test('edge case: rejects numbers shorter than 8 digits', () {
      expect(
        PatientFieldValidation.validateMobileNumber('1234567'),
        'Mobile number must be 8 to 15 digits.',
      );
    });

    test('edge case: rejects numbers longer than 15 digits', () {
      expect(
        PatientFieldValidation.validateMobileNumber('1234567890123456'),
        'Mobile number must be 8 to 15 digits.',
      );
    });

    test('trivial: accepts 8-digit boundary', () {
      expect(PatientFieldValidation.validateMobileNumber('12345678'), isNull);
    });

    test('trivial: accepts 15-digit boundary', () {
      expect(PatientFieldValidation.validateMobileNumber('123456789012345'), isNull);
    });
  });
}
