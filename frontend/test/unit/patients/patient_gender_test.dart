import 'package:ai_clinic/features/patients/domain/patient_gender.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PatientGender.tryParse', () {
    test('parses known enum wire values', () {
      expect(PatientGender.tryParse('male'), PatientGender.male);
      expect(PatientGender.tryParse('female'), PatientGender.female);
    });

    test('is case-insensitive and trims whitespace', () {
      expect(PatientGender.tryParse('  Male '), PatientGender.male);
      expect(PatientGender.tryParse('\tFEMALE\n'), PatientGender.female);
    });

    test('returns null for empty or unrecognized values', () {
      expect(PatientGender.tryParse(null), isNull);
      expect(PatientGender.tryParse(''), isNull);
      expect(PatientGender.tryParse('   '), isNull);
      expect(PatientGender.tryParse('nonbinary'), isNull);
    });

    test('parses extended enum wire values', () {
      expect(PatientGender.tryParse('other'), PatientGender.other);
      expect(PatientGender.tryParse('prefer_not_to_say'), PatientGender.preferNotToSay);
      expect(PatientGender.tryParse('unknown'), PatientGender.unknown);
    });

    test('stupid user input does not throw', () {
      expect(() => PatientGender.tryParse('null'), returnsNormally);
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
