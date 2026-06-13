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
  });
}
