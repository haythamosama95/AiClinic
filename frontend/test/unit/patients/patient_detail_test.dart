import 'package:ai_clinic/features/patients/domain/patient_detail.dart';
import 'package:ai_clinic/features/patients/domain/patient_gender.dart';
import 'package:ai_clinic/features/patients/domain/patient_marital_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PatientDetail.fromRow', () {
    test('parses full get_patient payload', () {
      final detail = PatientDetail.fromRow({
        'id': 'p1',
        'full_name': 'Sara Ali',
        'phone': '201111111111',
        'date_of_birth': '1985-03-20',
        'gender': 'female',
        'marital_status': 'married',
        'notes': 'Allergic to penicillin',
        'branch_id': 'b1',
        'branch_name': 'Downtown',
        'created_at': '2026-05-23T10:00:00.000Z',
        'updated_at': '2026-05-23T11:30:00.000Z',
        'created_by_display': 'Dr. Admin',
      });

      expect(detail, isNotNull);
      expect(detail!.gender, PatientGender.female);
      expect(detail.maritalStatus, PatientMaritalStatus.married);
      expect(detail.notes, 'Allergic to penicillin');
      expect(detail.createdByDisplay, 'Dr. Admin');
      expect(detail.dateOfBirth, DateTime(1985, 3, 20));
      expect(detail.updatedAt, DateTime.parse('2026-05-23T11:30:00.000Z'));
    });

    test('accepts created_by_name alias for audit display', () {
      final detail = PatientDetail.fromRow({
        'id': 'p1',
        'full_name': 'X',
        'branch_id': 'b1',
        'branch_name': 'B',
        'created_at': '2026-01-01T00:00:00Z',
        'updated_at': '2026-01-01T00:00:00Z',
        'created_by_name': 'Reception',
      });

      expect(detail!.createdByDisplay, 'Reception');
    });

    test('returns null without required audit timestamps', () {
      expect(
        PatientDetail.fromRow({
          'id': 'p1',
          'full_name': 'X',
          'branch_id': 'b1',
          'branch_name': 'B',
          'created_at': null,
          'updated_at': '2026-01-01T00:00:00Z',
        }),
        isNull,
      );
      expect(
        PatientDetail.fromRow({
          'id': 'p1',
          'full_name': 'X',
          'branch_id': 'b1',
          'branch_name': 'B',
          'created_at': 'bad',
          'updated_at': '2026-01-01T00:00:00Z',
        }),
        isNull,
      );
    });

    test('invalid gender is ignored (optional field)', () {
      final detail = PatientDetail.fromRow({
        'id': 'p1',
        'full_name': 'X',
        'gender': 'invalid',
        'branch_id': 'b1',
        'branch_name': 'B',
        'created_at': '2026-01-01T00:00:00Z',
        'updated_at': '2026-01-01T00:00:00Z',
      });

      expect(detail!.gender, isNull);
    });

    test('strips blank optional profile fields', () {
      final detail = PatientDetail.fromRow({
        'id': 'p1',
        'full_name': 'X',
        'phone': '  ',
        'notes': '\t',
        'branch_id': 'b1',
        'branch_name': 'B',
        'created_at': '2026-01-01T00:00:00Z',
        'updated_at': '2026-01-01T00:00:00Z',
      });

      expect(detail!.phone, isNull);
      expect(detail.notes, isNull);
    });

    test('copyWith supports optimistic edit state carry-over', () {
      final original = PatientDetail.fromRow({
        'id': 'p1',
        'full_name': 'X',
        'branch_id': 'b1',
        'branch_name': 'B',
        'created_at': '2026-01-01T00:00:00Z',
        'updated_at': '2026-01-01T00:00:00Z',
      })!;

      final stale = original.copyWith(fullName: 'Updated Elsewhere');
      expect(stale.fullName, 'Updated Elsewhere');
      expect(stale.updatedAt, original.updatedAt);
    });
  });
}
