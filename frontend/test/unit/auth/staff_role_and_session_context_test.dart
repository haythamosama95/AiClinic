import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import '../../helpers/auth_test_support.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StaffRole.tryParse', () {
    test('parses all wire values', () {
      for (final role in StaffRole.values) {
        expect(StaffRole.tryParse(role.wireValue), role);
      }
    });

    test('returns null for unknown role', () {
      expect(StaffRole.tryParse('superadmin'), isNull);
      expect(StaffRole.tryParse(null), isNull);
      expect(StaffRole.tryParse(''), isNull);
    });
  });

  group('AuthSessionContext', () {
    test('hasBranchAssignment reflects branchIds', () {
      expect(sampleAuthSessionContext(branchIds: []).hasBranchAssignment, isFalse);
      expect(sampleAuthSessionContext(branchIds: ['x']).hasBranchAssignment, isTrue);
    });

    test('copyWith updates activeBranchId only', () {
      const branchA = '00000000-0000-4000-8000-000000000001';
      const branchB = '00000000-0000-4000-8000-000000000002';
      final original = sampleAuthSessionContext(branchIds: [branchA, branchB]);
      final updated = original.copyWith(activeBranchId: branchB);

      expect(updated.activeBranchId, branchB);
      expect(updated.staffProfile, original.staffProfile);
      expect(updated.branchIds, original.branchIds);
    });
  });
}
