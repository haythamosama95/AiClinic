import 'package:ai_clinic/features/patients/domain/patient_gender.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PatientGender.tryParse', () {
    test('parses known enum wire values', () {
      expect(PatientGender.tryParse('male'), PatientGender.male);
      expect(PatientGender.tryParse('female'), PatientGender.female);
      expect(PatientGender.tryParse('other'), PatientGender.other);
      expect(PatientGender.tryParse('unknown'), PatientGender.unknown);
    });

    test('is case-insensitive and trims whitespace', () {
      expect(PatientGender.tryParse('  Male '), PatientGender.male);
      expect(PatientGender.tryParse('\tFEMALE\n'), PatientGender.female);
    });

    test('returns null for empty or unknown values', () {
      expect(PatientGender.tryParse(null), isNull);
      expect(PatientGender.tryParse(''), isNull);
      expect(PatientGender.tryParse('   '), isNull);
      expect(PatientGender.tryParse('nonbinary'), isNull);
      expect(PatientGender.tryParse('male/female'), isNull);
    });

    test('stupid user input does not throw', () {
      expect(() => PatientGender.tryParse('null'), returnsNormally);
      expect(() => PatientGender.tryParse('undefined'), returnsNormally);
      expect(PatientGender.tryParse('null'), isNull);
    });
  });

  group('PatientGender.wireValue', () {
    test('round-trips with tryParse', () {
      for (final gender in PatientGender.values) {
        expect(PatientGender.tryParse(gender.wireValue), gender);
      }
    });
  });
}
