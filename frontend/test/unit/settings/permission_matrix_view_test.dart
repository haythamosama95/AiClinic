import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/settings/domain/permission_matrix_row.dart';
import 'package:ai_clinic/features/settings/domain/permission_matrix_view.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PermissionMatrixView', () {
    test('fromRows groups grants by permission key sorted alphabetically', () {
      final view = PermissionMatrixView.fromRows([
        const PermissionMatrixRow(role: StaffRole.doctor, permissionKey: 'patients.view', isGranted: true),
        const PermissionMatrixRow(
          role: StaffRole.administrator,
          permissionKey: 'settings.manage_staff',
          isGranted: true,
        ),
        const PermissionMatrixRow(
          role: StaffRole.administrator,
          permissionKey: 'settings.manage_staff',
          isGranted: false,
        ),
      ]);

      expect(view.permissionKeys, ['patients.view', 'settings.manage_staff']);
      expect(view.isGranted(StaffRole.doctor, 'patients.view'), isTrue);
      expect(view.isGranted(StaffRole.administrator, 'settings.manage_staff'), isFalse);
      expect(view.isGranted(StaffRole.receptionist, 'patients.view'), isFalse);
    });

    test('edge case: missing role cell defaults to not granted', () {
      final view = PermissionMatrixView.fromRows([
        const PermissionMatrixRow(role: StaffRole.administrator, permissionKey: 'ai.access', isGranted: true),
      ]);

      expect(view.isGranted(StaffRole.labStaff, 'ai.access'), isFalse);
    });

    test('categoryGroups clusters keys by prefix before dot', () {
      final view = PermissionMatrixView.fromRows([
        const PermissionMatrixRow(
          role: StaffRole.administrator,
          permissionKey: 'settings.manage_staff',
          isGranted: true,
        ),
        const PermissionMatrixRow(role: StaffRole.administrator, permissionKey: 'patients.view', isGranted: true),
        const PermissionMatrixRow(role: StaffRole.administrator, permissionKey: 'patients.create', isGranted: true),
        const PermissionMatrixRow(role: StaffRole.administrator, permissionKey: 'ai.access', isGranted: true),
      ]);

      expect(view.categoryGroups.map((g) => g.category), ['ai', 'patients', 'settings']);
      expect(view.categoryGroups[1].permissionKeys, ['patients.create', 'patients.view']);
    });

    test('changesFrom lists grant differences between matrices', () {
      final saved = PermissionMatrixView.fromRows([
        const PermissionMatrixRow(role: StaffRole.doctor, permissionKey: 'patients.view', isGranted: true),
      ]);
      final working = saved.withGrant(role: StaffRole.doctor, permissionKey: 'patients.view', isGranted: false);

      final changes = working.changesFrom(saved).toList();
      expect(changes, hasLength(1));
      expect(changes.first.role, StaffRole.doctor);
      expect(changes.first.permissionKey, 'patients.view');
      expect(changes.first.isGranted, isFalse);
    });

    test('changesFrom reports multiple dirty cells', () {
      final saved = PermissionMatrixView.fromRows([
        const PermissionMatrixRow(role: StaffRole.doctor, permissionKey: 'patients.view', isGranted: true),
        const PermissionMatrixRow(
          role: StaffRole.administrator,
          permissionKey: 'settings.manage_staff',
          isGranted: true,
        ),
      ]);
      var working = saved.withGrant(role: StaffRole.doctor, permissionKey: 'patients.view', isGranted: false);
      working = working.withGrant(
        role: StaffRole.administrator,
        permissionKey: 'settings.manage_staff',
        isGranted: false,
      );

      expect(working.changesFrom(saved), hasLength(2));
    });

    test('equality compares grant values not map identity', () {
      final left = PermissionMatrixView.fromRows([
        const PermissionMatrixRow(role: StaffRole.administrator, permissionKey: 'ai.access', isGranted: true),
      ]);
      final right = left.withGrant(role: StaffRole.administrator, permissionKey: 'ai.access', isGranted: true);

      expect(left, right);
    });

    test('withGrant round-trip restores equality with saved matrix', () {
      final saved = PermissionMatrixView.fromRows([
        const PermissionMatrixRow(role: StaffRole.doctor, permissionKey: 'patients.view', isGranted: true),
      ]);
      final toggled = saved.withGrant(role: StaffRole.doctor, permissionKey: 'patients.view', isGranted: false);
      final restored = toggled.withGrant(role: StaffRole.doctor, permissionKey: 'patients.view', isGranted: true);

      expect(restored, saved);
      expect(toggled.changesFrom(saved), hasLength(1));
    });

    test('categoryLabel formats AI category', () {
      expect(PermissionMatrixView.categoryLabel('ai'), 'AI');
      expect(PermissionMatrixView.categoryLabel('patients'), 'Patients');
    });

    test('permissionCategory uses full key when no dot segment', () {
      expect(PermissionMatrixView.permissionCategory('legacy'), 'legacy');
    });

    test('permissionLabel uses segment after dot', () {
      expect(PermissionMatrixView.permissionLabel('patients.view'), 'View');
      expect(PermissionMatrixView.permissionLabel('settings.manage_branches'), 'Manage Branches');
    });

    test('fromRows fills every display role for each catalog permission', () {
      final view = PermissionMatrixView.fromRows([
        const PermissionMatrixRow(role: StaffRole.administrator, permissionKey: 'ai.access', isGranted: true),
      ]);

      for (final role in PermissionMatrixView.displayRoles) {
        expect(view.hasDefinedCell(role, 'ai.access'), isTrue);
      }
      expect(view.isGranted(StaffRole.receptionist, 'ai.access'), isFalse);
    });
  });
}
