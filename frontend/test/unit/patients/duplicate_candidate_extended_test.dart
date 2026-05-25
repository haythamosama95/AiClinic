import 'package:ai_clinic/features/patients/domain/duplicate_candidate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DuplicateCandidate.hashCode', () {
    test('equal candidates have equal hash codes', () {
      const a = DuplicateCandidate(id: '1', fullName: 'X', branchName: 'B', phone: '123');
      const b = DuplicateCandidate(id: '1', fullName: 'X', branchName: 'B', phone: '123');

      expect(a.hashCode, b.hashCode);
    });

    test('different candidates likely have different hash codes', () {
      const a = DuplicateCandidate(id: '1', fullName: 'X', branchName: 'B');
      const b = DuplicateCandidate(id: '2', fullName: 'Y', branchName: 'C');

      expect(a.hashCode, isNot(b.hashCode));
    });
  });

  group('DuplicateCandidate equality with all fields', () {
    test('equal when all fields match including optional', () {
      final a = DuplicateCandidate(
        id: 'dup-1',
        fullName: 'Ahmed',
        branchName: 'Main',
        phone: '201000000001',
        dateOfBirth: DateTime(1990, 5, 15),
      );
      final b = DuplicateCandidate(
        id: 'dup-1',
        fullName: 'Ahmed',
        branchName: 'Main',
        phone: '201000000001',
        dateOfBirth: DateTime(1990, 5, 15),
      );

      expect(a == b, isTrue);
    });

    test('not equal when phone differs', () {
      const a = DuplicateCandidate(id: '1', fullName: 'X', branchName: 'B', phone: '111');
      const b = DuplicateCandidate(id: '1', fullName: 'X', branchName: 'B', phone: '222');

      expect(a == b, isFalse);
    });

    test('not equal when dateOfBirth differs', () {
      final a = DuplicateCandidate(id: '1', fullName: 'X', branchName: 'B', dateOfBirth: DateTime(1990, 1, 1));
      final b = DuplicateCandidate(id: '1', fullName: 'X', branchName: 'B', dateOfBirth: DateTime(1991, 1, 1));

      expect(a == b, isFalse);
    });

    test('not equal when branchName differs', () {
      const a = DuplicateCandidate(id: '1', fullName: 'X', branchName: 'Main');
      const b = DuplicateCandidate(id: '1', fullName: 'X', branchName: 'South');

      expect(a == b, isFalse);
    });

    test('not equal when fullName differs', () {
      const a = DuplicateCandidate(id: '1', fullName: 'Ahmed', branchName: 'B');
      const b = DuplicateCandidate(id: '1', fullName: 'Sara', branchName: 'B');

      expect(a == b, isFalse);
    });

    test('not equal to other types', () {
      const candidate = DuplicateCandidate(id: '1', fullName: 'X', branchName: 'B');
      // ignore: unrelated_type_equality_checks
      expect(candidate == 'not a candidate', isFalse);
    });

    test('identical instances are equal', () {
      const candidate = DuplicateCandidate(id: '1', fullName: 'X', branchName: 'B');
      expect(identical(candidate, candidate), isTrue);
      expect(candidate == candidate, isTrue);
    });
  });

  group('DuplicateCandidate.fromRow extended edge cases', () {
    test('id as integer is coerced to string', () {
      final candidate = DuplicateCandidate.fromRow({'id': 42, 'full_name': 'Test', 'branch_name': 'Main'});

      expect(candidate!.id, '42');
    });

    test('phone with only whitespace is treated as null', () {
      final candidate = DuplicateCandidate.fromRow({
        'id': '1',
        'full_name': 'Test',
        'branch_name': 'Main',
        'phone': '   ',
      });

      expect(candidate!.phone, isNull);
    });

    test('date_of_birth as DateTime object is normalized to date-only', () {
      final candidate = DuplicateCandidate.fromRow({
        'id': '1',
        'full_name': 'Test',
        'branch_name': 'Main',
        'date_of_birth': DateTime(2000, 6, 15, 23, 59),
      });

      expect(candidate!.dateOfBirth, DateTime.utc(2000, 6, 15));
    });

    test('full_name is trimmed', () {
      final candidate = DuplicateCandidate.fromRow({'id': '1', 'full_name': '  Ahmed Hassan  ', 'branch_name': 'Main'});

      expect(candidate!.fullName, 'Ahmed Hassan');
    });

    test('branch_name is trimmed', () {
      final candidate = DuplicateCandidate.fromRow({'id': '1', 'full_name': 'X', 'branch_name': '  Main Branch  '});

      expect(candidate!.branchName, 'Main Branch');
    });

    test('returns null when id is null', () {
      expect(DuplicateCandidate.fromRow({'full_name': 'X', 'branch_name': 'B'}), isNull);
    });

    test('missing branch_name returns null', () {
      expect(DuplicateCandidate.fromRow({'id': '1', 'full_name': 'X'}), isNull);
    });
  });
}
