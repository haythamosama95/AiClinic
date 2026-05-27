import 'package:ai_clinic/features/patients/domain/patient_marital_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PatientMaritalStatus.tryParse', () {
    test('parses known enum wire values', () {
      expect(PatientMaritalStatus.tryParse('single'), PatientMaritalStatus.single);
      expect(PatientMaritalStatus.tryParse('married'), PatientMaritalStatus.married);
      expect(PatientMaritalStatus.tryParse('divorced'), PatientMaritalStatus.divorced);
      expect(PatientMaritalStatus.tryParse('widowed'), PatientMaritalStatus.widowed);
    });

    test('is case-insensitive and trims whitespace', () {
      expect(PatientMaritalStatus.tryParse('  Single '), PatientMaritalStatus.single);
      expect(PatientMaritalStatus.tryParse('MARRIED'), PatientMaritalStatus.married);
      expect(PatientMaritalStatus.tryParse('\tDivorced\n'), PatientMaritalStatus.divorced);
      expect(PatientMaritalStatus.tryParse('  WIDOWED  '), PatientMaritalStatus.widowed);
    });

    test('returns null for empty or unknown values', () {
      expect(PatientMaritalStatus.tryParse(null), isNull);
      expect(PatientMaritalStatus.tryParse(''), isNull);
      expect(PatientMaritalStatus.tryParse('   '), isNull);
      expect(PatientMaritalStatus.tryParse('separated'), isNull);
      expect(PatientMaritalStatus.tryParse('engaged'), isNull);
      expect(PatientMaritalStatus.tryParse('unknown'), isNull);
    });

    test('garbage input does not throw', () {
      expect(() => PatientMaritalStatus.tryParse('null'), returnsNormally);
      expect(PatientMaritalStatus.tryParse('null'), isNull);
      expect(PatientMaritalStatus.tryParse('123'), isNull);
      expect(PatientMaritalStatus.tryParse('true'), isNull);
    });
  });

  group('PatientMaritalStatus.wireValue', () {
    test('round-trips with tryParse for all values', () {
      for (final status in PatientMaritalStatus.values) {
        expect(PatientMaritalStatus.tryParse(status.wireValue), status);
      }
    });

    test('wire values are lowercase strings', () {
      for (final status in PatientMaritalStatus.values) {
        expect(status.wireValue, status.wireValue.toLowerCase());
      }
    });
  });

  group('PatientMaritalStatus.label', () {
    test('returns human-readable labels for all values', () {
      expect(PatientMaritalStatus.single.label, 'Single');
      expect(PatientMaritalStatus.married.label, 'Married');
      expect(PatientMaritalStatus.divorced.label, 'Divorced');
      expect(PatientMaritalStatus.widowed.label, 'Widowed');
    });

    test('labels are capitalized and non-empty', () {
      for (final status in PatientMaritalStatus.values) {
        expect(status.label, isNotEmpty);
        expect(status.label[0], status.label[0].toUpperCase());
      }
    });

    test('all enum values have distinct labels', () {
      final labels = PatientMaritalStatus.values.map((s) => s.label).toSet();
      expect(labels.length, PatientMaritalStatus.values.length);
    });
  });
}
