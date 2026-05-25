import 'package:ai_clinic/core/auth/permission_service.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:ai_clinic/testing/auth_test_support.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PermissionService patient methods', () {
    test('canViewPatients returns true when patients.view is granted', () {
      final service = PermissionService(
        sampleAuthSessionContext(permissions: {PermissionKeys.patientsView}),
      );

      expect(service.canViewPatients(), isTrue);
    });

    test('canViewPatients returns false without patients.view', () {
      final service = PermissionService(
        sampleAuthSessionContext(permissions: {PermissionKeys.aiAccess}),
      );

      expect(service.canViewPatients(), isFalse);
    });

    test('canCreatePatients returns true when patients.create is granted', () {
      final service = PermissionService(
        sampleAuthSessionContext(permissions: {PermissionKeys.patientsCreate}),
      );

      expect(service.canCreatePatients(), isTrue);
    });

    test('canCreatePatients returns false without patients.create', () {
      final service = PermissionService(
        sampleAuthSessionContext(permissions: {PermissionKeys.patientsView}),
      );

      expect(service.canCreatePatients(), isFalse);
    });

    test('canEditPatients returns true when patients.edit is granted', () {
      final service = PermissionService(
        sampleAuthSessionContext(permissions: {PermissionKeys.patientsEdit}),
      );

      expect(service.canEditPatients(), isTrue);
    });

    test('canEditPatients returns false without patients.edit', () {
      final service = PermissionService(
        sampleAuthSessionContext(permissions: {PermissionKeys.patientsView, PermissionKeys.patientsCreate}),
      );

      expect(service.canEditPatients(), isFalse);
    });

    test('canDeletePatients returns true when patients.delete is granted', () {
      final service = PermissionService(
        sampleAuthSessionContext(permissions: {PermissionKeys.patientsDelete}),
      );

      expect(service.canDeletePatients(), isTrue);
    });

    test('canDeletePatients returns false without patients.delete', () {
      final service = PermissionService(
        sampleAuthSessionContext(permissions: RolePermissionSeed.doctor),
      );

      expect(service.canDeletePatients(), isFalse);
    });
  });

  group('PermissionService edge cases', () {
    test('null context denies all patient permissions', () {
      const service = PermissionService(null);

      expect(service.canViewPatients(), isFalse);
      expect(service.canCreatePatients(), isFalse);
      expect(service.canEditPatients(), isFalse);
      expect(service.canDeletePatients(), isFalse);
    });

    test('no branch assignment denies all patient permissions', () {
      final service = PermissionService(
        sampleAuthSessionContext(
          permissions: RolePermissionSeed.owner,
          branchIds: const [],
        ),
      );

      expect(service.canViewPatients(), isFalse);
      expect(service.canCreatePatients(), isFalse);
      expect(service.canEditPatients(), isFalse);
      expect(service.canDeletePatients(), isFalse);
    });

    test('empty permission set denies all patient permissions', () {
      final service = PermissionService(
        sampleAuthSessionContext(permissions: const {}),
      );

      expect(service.canViewPatients(), isFalse);
      expect(service.canCreatePatients(), isFalse);
      expect(service.canEditPatients(), isFalse);
      expect(service.canDeletePatients(), isFalse);
    });

    test('owner role has all patient permissions by seed', () {
      final service = PermissionService(
        sampleAuthSessionContext(permissions: RolePermissionSeed.owner),
      );

      expect(service.canViewPatients(), isTrue);
      expect(service.canCreatePatients(), isTrue);
      expect(service.canEditPatients(), isTrue);
      expect(service.canDeletePatients(), isTrue);
    });

    test('doctor role: view + create but not edit/delete', () {
      final service = PermissionService(
        sampleAuthSessionContext(permissions: RolePermissionSeed.doctor),
      );

      expect(service.canViewPatients(), isTrue);
      expect(service.canCreatePatients(), isTrue);
      expect(service.canEditPatients(), isFalse);
      expect(service.canDeletePatients(), isFalse);
    });

    test('receptionist role: view only', () {
      final service = PermissionService(
        sampleAuthSessionContext(permissions: RolePermissionSeed.receptionist),
      );

      expect(service.canViewPatients(), isTrue);
      expect(service.canCreatePatients(), isFalse);
      expect(service.canEditPatients(), isFalse);
      expect(service.canDeletePatients(), isFalse);
    });

    test('lab staff role: view only', () {
      final service = PermissionService(
        sampleAuthSessionContext(permissions: RolePermissionSeed.labStaff),
      );

      expect(service.canViewPatients(), isTrue);
      expect(service.canCreatePatients(), isFalse);
      expect(service.canEditPatients(), isFalse);
      expect(service.canDeletePatients(), isFalse);
    });

    test('hasAnyPermission with patient keys', () {
      final service = PermissionService(
        sampleAuthSessionContext(permissions: {PermissionKeys.patientsView}),
      );

      expect(
        service.hasAnyPermission([PermissionKeys.patientsView, PermissionKeys.patientsCreate]),
        isTrue,
      );
      expect(
        service.hasAnyPermission([PermissionKeys.patientsEdit, PermissionKeys.patientsDelete]),
        isFalse,
      );
    });

    test('hasAnyPermission with empty keys returns false', () {
      final service = PermissionService(
        sampleAuthSessionContext(permissions: RolePermissionSeed.owner),
      );

      expect(service.hasAnyPermission([]), isFalse);
    });

    test('requirePermission throws PermissionDeniedException when missing', () {
      final service = PermissionService(
        sampleAuthSessionContext(permissions: {PermissionKeys.patientsView}),
      );

      expect(
        () => service.requirePermission(PermissionKeys.patientsDelete),
        throwsA(isA<PermissionDeniedException>()),
      );
    });

    test('requirePermission does not throw when granted', () {
      final service = PermissionService(
        sampleAuthSessionContext(permissions: {PermissionKeys.patientsView}),
      );

      expect(
        () => service.requirePermission(PermissionKeys.patientsView),
        returnsNormally,
      );
    });
  });
}
