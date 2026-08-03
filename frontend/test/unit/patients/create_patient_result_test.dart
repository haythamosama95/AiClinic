import 'package:ai_clinic/features/patients/domain/create_patient_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CreatePatientResult.fromJson', () {
    test('trivial: parses patient_id and mrn', () {
      final result = CreatePatientResult.fromJson({
        'patient_id': 'p-42',
        'mrn': 'MRN-000042',
      });

      expect(result.patientId, 'p-42');
      expect(result.mrn, 'MRN-000042');
    });

    test('advanced: coerces numeric ids to strings', () {
      final result = CreatePatientResult.fromJson({
        'patient_id': 99,
        'mrn': 1001,
      });

      expect(result.patientId, '99');
      expect(result.mrn, '1001');
    });

    test('invalid state: throws when patient_id is missing', () {
      expect(
        () => CreatePatientResult.fromJson({'mrn': 'MRN-000001'}),
        throwsA(isA<FormatException>()),
      );
    });

    test('invalid state: throws when patient_id is empty string', () {
      expect(
        () => CreatePatientResult.fromJson({'patient_id': '', 'mrn': 'MRN-000001'}),
        throwsA(isA<FormatException>()),
      );
    });

    test('edge case: whitespace-only patient_id is accepted without trim', () {
      final result = CreatePatientResult.fromJson({
        'patient_id': '  ',
        'mrn': 'MRN-000001',
      });

      expect(result.patientId, '  ');
    });

    test('invalid state: throws when mrn is missing', () {
      expect(
        () => CreatePatientResult.fromJson({'patient_id': 'p1'}),
        throwsA(isA<FormatException>()),
      );
    });

    test('invalid state: throws when mrn is blank', () {
      expect(
        () => CreatePatientResult.fromJson({'patient_id': 'p1', 'mrn': ''}),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('CreatePatientResult.copyWith', () {
    const original = CreatePatientResult(patientId: 'p1', mrn: 'MRN-000001');

    test('advanced: overriding patientId preserves mrn', () {
      final updated = original.copyWith(patientId: 'p2');

      expect(updated.patientId, 'p2');
      expect(updated.mrn, original.mrn);
    });

    test('advanced: overriding mrn preserves patientId', () {
      final updated = original.copyWith(mrn: 'MRN-000099');

      expect(updated.mrn, 'MRN-000099');
      expect(updated.patientId, original.patientId);
    });
  });

  group('CreatePatientResult equality', () {
    test('trivial: equal instances share hashCode', () {
      const a = CreatePatientResult(patientId: 'p1', mrn: 'MRN-000001');
      const b = CreatePatientResult(patientId: 'p1', mrn: 'MRN-000001');

      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('edge case: differing patientId is unequal', () {
      const a = CreatePatientResult(patientId: 'p1', mrn: 'MRN-000001');
      const b = CreatePatientResult(patientId: 'p2', mrn: 'MRN-000001');

      expect(a == b, isFalse);
    });

    test('edge case: differing mrn is unequal', () {
      const a = CreatePatientResult(patientId: 'p1', mrn: 'MRN-000001');
      const b = CreatePatientResult(patientId: 'p1', mrn: 'MRN-000002');

      expect(a == b, isFalse);
    });
  });
}
