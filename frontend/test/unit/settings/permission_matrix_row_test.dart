import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/settings/domain/permission_matrix_row.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PermissionMatrixRow.fromRow', () {
    test('parses granted permission for owner role', () {
      final row = PermissionMatrixRow.fromRow({
        'role': 'administrator',
        'permission_key': 'settings.manage_staff',
        'is_granted': true,
      });

      expect(row, isNotNull);
      expect(row!.role, StaffRole.administrator);
      expect(row.permissionKey, 'settings.manage_staff');
      expect(row.isGranted, isTrue);
    });

    test('returns null when role or permission_key invalid', () {
      expect(
        PermissionMatrixRow.fromRow({'role': 'nope', 'permission_key': 'settings.manage_staff', 'is_granted': true}),
        isNull,
      );
      expect(PermissionMatrixRow.fromRow({'role': 'administrator', 'permission_key': '', 'is_granted': true}), isNull);
      expect(PermissionMatrixRow.fromRow({'role': 'administrator', 'permission_key': '   ', 'is_granted': true}), isNull);
      expect(PermissionMatrixRow.fromRow({}), isNull);
    });

    test('parses is_granted from bool and string', () {
      expect(
        PermissionMatrixRow.fromRow({
          'role': 'administrator',
          'permission_key': 'patients.view',
          'is_granted': 'true',
        })!.isGranted,
        isTrue,
      );
      expect(
        PermissionMatrixRow.fromRow({
          'role': 'doctor',
          'permission_key': 'patients.view',
          'is_granted': 'false',
        })!.isGranted,
        isFalse,
      );
      expect(
        PermissionMatrixRow.fromRow({
          'role': 'doctor',
          'permission_key': 'patients.view',
          'is_granted': '1',
        })!.isGranted,
        isTrue,
      );
    });

    test('trims permission_key whitespace', () {
      final row = PermissionMatrixRow.fromRow({
        'role': 'receptionist',
        'permission_key': '  patients.view  ',
        'is_granted': false,
      });

      expect(row!.permissionKey, 'patients.view');
    });
  });

  group('PermissionMatrixRow.copyWith and equality', () {
    test('toggle grant via copyWith', () {
      const row = PermissionMatrixRow(
        role: StaffRole.administrator,
        permissionKey: 'settings.manage_branches',
        isGranted: false,
      );
      final granted = row.copyWith(isGranted: true);

      expect(granted.isGranted, isTrue);
      expect(granted.role, StaffRole.administrator);
      expect(row == granted, isFalse);
    });

    test('equality is value-based on role, key, grant', () {
      const a = PermissionMatrixRow(role: StaffRole.labStaff, permissionKey: 'patients.view', isGranted: true);
      const b = PermissionMatrixRow(role: StaffRole.labStaff, permissionKey: 'patients.view', isGranted: true);
      const c = PermissionMatrixRow(role: StaffRole.labStaff, permissionKey: 'patients.view', isGranted: false);

      expect(a, equals(b));
      expect(a == c, isFalse);
    });
  });
}
