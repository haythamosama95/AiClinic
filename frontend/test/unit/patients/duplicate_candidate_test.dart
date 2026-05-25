import 'package:ai_clinic/features/patients/domain/duplicate_candidate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DuplicateCandidate.fromRow', () {
    test('parses duplicate check candidate row', () {
      final candidate = DuplicateCandidate.fromRow({
        'id': 'dup-1',
        'full_name': 'Mohamed Ibrahim',
        'phone': '201000000001',
        'date_of_birth': '1992-07-01',
        'branch_name': 'North Branch',
      });

      expect(candidate, isNotNull);
      expect(candidate!.fullName, 'Mohamed Ibrahim');
      expect(candidate.phone, '201000000001');
      expect(candidate.dateOfBirth, DateTime.utc(1992, 7, 1));
      expect(candidate.branchName, 'North Branch');
    });

    test('returns null when id, name, or branch missing', () {
      expect(DuplicateCandidate.fromRow({'id': '', 'full_name': 'X', 'branch_name': 'B'}), isNull);
      expect(DuplicateCandidate.fromRow({'id': '1', 'full_name': '  ', 'branch_name': 'B'}), isNull);
      expect(DuplicateCandidate.fromRow({'id': '1', 'full_name': 'X', 'branch_name': ''}), isNull);
    });

    test('allows partial identifier matches (phone-only advisory)', () {
      final candidate = DuplicateCandidate.fromRow({
        'id': 'dup-2',
        'full_name': 'Unknown Match',
        'phone': '20999999999',
        'branch_name': 'Main',
      });

      expect(candidate!.dateOfBirth, isNull);
    });

    test('stupid user: garbage date does not crash parsing', () {
      final candidate = DuplicateCandidate.fromRow({
        'id': 'dup-3',
        'full_name': 'X',
        'date_of_birth': 'yesterday',
        'branch_name': 'Main',
      });

      expect(candidate!.dateOfBirth, isNull);
    });

    test('equality distinguishes candidates by id', () {
      const a = DuplicateCandidate(id: '1', fullName: 'A', branchName: 'B');
      const b = DuplicateCandidate(id: '2', fullName: 'A', branchName: 'B');

      expect(a == b, isFalse);
    });
  });
}
