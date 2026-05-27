import 'package:ai_clinic/features/patients/domain/patient_detail.dart';
import 'package:ai_clinic/features/patients/domain/patient_gender.dart';
import 'package:ai_clinic/features/patients/domain/patient_marital_status.dart';
import 'package:flutter_test/flutter_test.dart';

PatientDetail _makeDetail({
  String id = 'p1',
  String fullName = 'Ahmed',
  String branchId = 'b1',
  String branchName = 'Main',
  String? phone,
  DateTime? dateOfBirth,
  PatientGender? gender,
  PatientMaritalStatus? maritalStatus,
  String? notes,
  String? createdByDisplay,
}) {
  return PatientDetail(
    id: id,
    fullName: fullName,
    branchId: branchId,
    branchName: branchName,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
    phone: phone,
    dateOfBirth: dateOfBirth,
    gender: gender,
    maritalStatus: maritalStatus,
    notes: notes,
    createdByDisplay: createdByDisplay,
  );
}

void main() {
  group('PatientDetail equality', () {
    test('equal when all fields match', () {
      final a = _makeDetail();
      final b = _makeDetail();

      expect(a == b, isTrue);
      expect(a.hashCode, b.hashCode);
    });

    test('not equal when id differs', () {
      expect(_makeDetail(id: 'p1') == _makeDetail(id: 'p2'), isFalse);
    });

    test('not equal when fullName differs', () {
      expect(_makeDetail(fullName: 'Ahmed') == _makeDetail(fullName: 'Sara'), isFalse);
    });

    test('not equal when phone differs', () {
      expect(_makeDetail(phone: '111') == _makeDetail(phone: '222'), isFalse);
    });

    test('not equal when one has phone and other does not', () {
      expect(_makeDetail(phone: '111') == _makeDetail(), isFalse);
    });

    test('not equal when gender differs', () {
      expect(
        _makeDetail(gender: PatientGender.male) == _makeDetail(gender: PatientGender.female),
        isFalse,
      );
    });

    test('not equal when maritalStatus differs', () {
      expect(
        _makeDetail(maritalStatus: PatientMaritalStatus.single) ==
            _makeDetail(maritalStatus: PatientMaritalStatus.married),
        isFalse,
      );
    });

    test('not equal when notes differ', () {
      expect(_makeDetail(notes: 'A') == _makeDetail(notes: 'B'), isFalse);
    });

    test('not equal when branchId differs', () {
      expect(_makeDetail(branchId: 'b1') == _makeDetail(branchId: 'b2'), isFalse);
    });

    test('not equal when branchName differs', () {
      expect(_makeDetail(branchName: 'Main') == _makeDetail(branchName: 'South'), isFalse);
    });

    test('not equal when createdByDisplay differs', () {
      expect(
        _makeDetail(createdByDisplay: 'Admin') == _makeDetail(createdByDisplay: 'Doctor'),
        isFalse,
      );
    });

    test('not equal to different runtime type', () {
      // ignore: unrelated_type_equality_checks
      expect(_makeDetail() == 'not a detail', isFalse);
    });

    test('identical instances are equal', () {
      final detail = _makeDetail();
      expect(identical(detail, detail), isTrue);
      expect(detail == detail, isTrue);
    });
  });

  group('PatientDetail.copyWith advanced', () {
    test('can replace nullable fields with non-null values', () {
      final original = _makeDetail();
      final updated = original.copyWith(
        phone: '201000000001',
        dateOfBirth: DateTime(1990, 5, 15),
        gender: PatientGender.male,
        maritalStatus: PatientMaritalStatus.single,
        notes: 'Test notes',
        createdByDisplay: 'Dr. Test',
      );

      expect(updated.phone, '201000000001');
      expect(updated.dateOfBirth, DateTime(1990, 5, 15));
      expect(updated.gender, PatientGender.male);
      expect(updated.maritalStatus, PatientMaritalStatus.single);
      expect(updated.notes, 'Test notes');
      expect(updated.createdByDisplay, 'Dr. Test');
    });

    test('can replace id and branch', () {
      final updated = _makeDetail().copyWith(
        id: 'new-id',
        branchId: 'new-branch',
        branchName: 'New Branch',
      );

      expect(updated.id, 'new-id');
      expect(updated.branchId, 'new-branch');
      expect(updated.branchName, 'New Branch');
    });

    test('can replace timestamps', () {
      final original = _makeDetail();
      final newCreated = DateTime.utc(2025, 1, 1);
      final newUpdated = DateTime.utc(2025, 6, 15);

      final updated = original.copyWith(createdAt: newCreated, updatedAt: newUpdated);

      expect(updated.createdAt, newCreated);
      expect(updated.updatedAt, newUpdated);
    });
  });

  group('PatientDetail.fromRow edge cases', () {
    test('returns null when id is null', () {
      expect(
        PatientDetail.fromRow({
          'full_name': 'X',
          'branch_id': 'b1',
          'branch_name': 'B',
          'created_at': '2026-01-01T00:00:00Z',
          'updated_at': '2026-01-01T00:00:00Z',
        }),
        isNull,
      );
    });

    test('returns null when full_name is null', () {
      expect(
        PatientDetail.fromRow({
          'id': 'p1',
          'branch_id': 'b1',
          'branch_name': 'B',
          'created_at': '2026-01-01T00:00:00Z',
          'updated_at': '2026-01-01T00:00:00Z',
        }),
        isNull,
      );
    });

    test('returns null when branch_id is null', () {
      expect(
        PatientDetail.fromRow({
          'id': 'p1',
          'full_name': 'X',
          'branch_name': 'B',
          'created_at': '2026-01-01T00:00:00Z',
          'updated_at': '2026-01-01T00:00:00Z',
        }),
        isNull,
      );
    });

    test('returns null when branch_name is null', () {
      expect(
        PatientDetail.fromRow({
          'id': 'p1',
          'full_name': 'X',
          'branch_id': 'b1',
          'created_at': '2026-01-01T00:00:00Z',
          'updated_at': '2026-01-01T00:00:00Z',
        }),
        isNull,
      );
    });

    test('returns null when updated_at is null', () {
      expect(
        PatientDetail.fromRow({
          'id': 'p1',
          'full_name': 'X',
          'branch_id': 'b1',
          'branch_name': 'B',
          'created_at': '2026-01-01T00:00:00Z',
        }),
        isNull,
      );
    });

    test('returns null when created_at is unparseable', () {
      expect(
        PatientDetail.fromRow({
          'id': 'p1',
          'full_name': 'X',
          'branch_id': 'b1',
          'branch_name': 'B',
          'created_at': 'not-a-date',
          'updated_at': '2026-01-01T00:00:00Z',
        }),
        isNull,
      );
    });

    test('invalid marital_status is ignored (optional)', () {
      final detail = PatientDetail.fromRow({
        'id': 'p1',
        'full_name': 'X',
        'marital_status': 'engaged',
        'branch_id': 'b1',
        'branch_name': 'B',
        'created_at': '2026-01-01T00:00:00Z',
        'updated_at': '2026-01-01T00:00:00Z',
      });

      expect(detail!.maritalStatus, isNull);
    });

    test('prefers created_by_display over created_by_name', () {
      final detail = PatientDetail.fromRow({
        'id': 'p1',
        'full_name': 'X',
        'branch_id': 'b1',
        'branch_name': 'B',
        'created_at': '2026-01-01T00:00:00Z',
        'updated_at': '2026-01-01T00:00:00Z',
        'created_by_display': 'Display Name',
        'created_by_name': 'Fallback Name',
      });

      expect(detail!.createdByDisplay, 'Display Name');
    });

    test('falls back to created_by_name when created_by_display is absent', () {
      final detail = PatientDetail.fromRow({
        'id': 'p1',
        'full_name': 'X',
        'branch_id': 'b1',
        'branch_name': 'B',
        'created_at': '2026-01-01T00:00:00Z',
        'updated_at': '2026-01-01T00:00:00Z',
        'created_by_name': 'Fallback',
      });

      expect(detail!.createdByDisplay, 'Fallback');
    });

    test('blank created_by_display is treated as null', () {
      final detail = PatientDetail.fromRow({
        'id': 'p1',
        'full_name': 'X',
        'branch_id': 'b1',
        'branch_name': 'B',
        'created_at': '2026-01-01T00:00:00Z',
        'updated_at': '2026-01-01T00:00:00Z',
        'created_by_display': '   ',
      });

      expect(detail!.createdByDisplay, isNull);
    });
  });
}
