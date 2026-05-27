import 'package:ai_clinic/core/auth/permission_service.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import '../../helpers/auth_test_support.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PermissionService', () {
    test('hasPermission is false when context is null', () {
      const service = PermissionService(null);
      expect(service.hasPermission(PermissionKeys.patientsView), isFalse);
      expect(service.hasPermission(''), isFalse);
    });

    test('hasPermission is false when branchIds is empty even with grants', () {
      final context = sampleAuthSessionContext(branchIds: [], permissions: RolePermissionSeed.owner);
      final service = PermissionService(context);

      expect(service.hasPermission(PermissionKeys.manageStaff), isFalse);
      expect(service.hasPermission(PermissionKeys.patientsView), isFalse);
    });

    test('hasPermission is false for empty or nonsense permission keys', () {
      final context = sampleAuthSessionContext(permissions: RolePermissionSeed.owner);
      final service = PermissionService(context);

      expect(service.hasPermission(''), isFalse);
      expect(service.hasPermission('   '), isFalse);
      expect(service.hasPermission('patients.read'), isFalse);
      expect(service.hasPermission('SETTINGS.MANAGE_STAFF'), isFalse);
    });

    test('requirePermission throws PermissionDeniedException when denied', () {
      final context = sampleAuthSessionContext(permissions: {});
      final service = PermissionService(context);

      expect(
        () => service.requirePermission(PermissionKeys.manageStaff),
        throwsA(isA<PermissionDeniedException>().having((e) => e.message, 'message', contains('permission'))),
      );
    });

    test('requirePermission succeeds when granted', () {
      final context = sampleAuthSessionContext(permissions: {PermissionKeys.patientsView});
      final service = PermissionService(context);

      expect(() => service.requirePermission(PermissionKeys.patientsView), returnsNormally);
    });

    test('hasAnyPermission returns false for empty key list', () {
      final context = sampleAuthSessionContext(permissions: RolePermissionSeed.owner);
      final service = PermissionService(context);

      expect(service.hasAnyPermission(const []), isFalse);
    });

    test('hasAnyPermission returns true when one key is granted', () {
      final context = sampleAuthSessionContext(permissions: {PermissionKeys.patientsView});
      final service = PermissionService(context);

      expect(service.hasAnyPermission([PermissionKeys.manageStaff, PermissionKeys.patientsView]), isTrue);
    });

    test('hasAnyPermission returns false when none match', () {
      final context = sampleAuthSessionContext(permissions: {PermissionKeys.patientsView});
      final service = PermissionService(context);

      expect(service.hasAnyPermission([PermissionKeys.manageStaff, PermissionKeys.analyticsView]), isFalse);
    });

    group('seed matrix per role', () {
      for (final role in StaffRole.values) {
        test('${role.wireValue} grants match RolePermissionSeed expectations', () {
          final service = PermissionService(
            sampleAuthSessionContext(role: role, permissions: RolePermissionSeed.forRole(role)),
          );

          for (final key in RolePermissionSeed.forRole(role)) {
            expect(service.hasPermission(key), isTrue, reason: 'expected grant for $key');
          }

          if (role == StaffRole.doctor || role == StaffRole.labStaff) {
            expect(service.hasPermission(PermissionKeys.manageStaff), isFalse);
            expect(service.hasPermission(PermissionKeys.analyticsView), isFalse);
          }

          if (role == StaffRole.receptionist) {
            expect(service.hasPermission(PermissionKeys.invoicesCreate), isTrue);
            expect(service.hasPermission(PermissionKeys.aiAccess), isFalse);
          }

          if (role == StaffRole.labStaff) {
            expect(service.hasPermission(PermissionKeys.patientsCreate), isFalse);
            expect(service.hasPermission(PermissionKeys.patientsView), isTrue);
          }
        });
      }
    });

    test('V1-3 patient helpers reflect grants', () {
      final full = PermissionService(
        sampleAuthSessionContext(
          permissions: {
            PermissionKeys.patientsView,
            PermissionKeys.patientsCreate,
            PermissionKeys.patientsEdit,
            PermissionKeys.patientsDelete,
          },
        ),
      );
      final viewOnly = PermissionService(sampleAuthSessionContext(permissions: {PermissionKeys.patientsView}));

      expect(full.canViewPatients(), isTrue);
      expect(full.canCreatePatients(), isTrue);
      expect(full.canEditPatients(), isTrue);
      expect(full.canDeletePatients(), isTrue);

      expect(viewOnly.canViewPatients(), isTrue);
      expect(viewOnly.canCreatePatients(), isFalse);
      expect(viewOnly.canEditPatients(), isFalse);
      expect(viewOnly.canDeletePatients(), isFalse);
    });

    test('owner and administrator share staff settings grant; doctor does not', () {
      final owner = PermissionService(
        sampleAuthSessionContext(role: StaffRole.owner, permissions: RolePermissionSeed.owner),
      );
      final admin = PermissionService(
        sampleAuthSessionContext(role: StaffRole.administrator, permissions: RolePermissionSeed.administrator),
      );
      final doctor = PermissionService(
        sampleAuthSessionContext(role: StaffRole.doctor, permissions: RolePermissionSeed.doctor),
      );

      expect(owner.hasPermission(PermissionKeys.manageStaff), isTrue);
      expect(admin.hasPermission(PermissionKeys.manageStaff), isTrue);
      expect(doctor.hasPermission(PermissionKeys.manageStaff), isFalse);
    });
  });
}
