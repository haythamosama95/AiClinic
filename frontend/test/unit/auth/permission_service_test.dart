import 'package:ai_clinic/core/auth/permission_service.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/testing/auth_test_support.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PermissionService', () {
    test('hasPermission is false when context is null', () {
      const service = PermissionService(null);
      expect(service.hasPermission('patients.read'), isFalse);
    });

    test('hasPermission is false when branchIds is empty', () {
      final context = sampleAuthSessionContext(branchIds: []);
      final service = PermissionService(context);
      expect(service.hasPermission('patients.read'), isFalse);
    });

    test('requirePermission throws when denied', () {
      final context = sampleAuthSessionContext(permissions: {});
      final service = PermissionService(context);
      expect(() => service.requirePermission('patients.read'), throwsA(isA<PermissionDeniedException>()));
    });

    test('hasAnyPermission returns true when one key is granted', () {
      final context = sampleAuthSessionContext(permissions: {'patients.read'});
      final service = PermissionService(context);
      expect(service.hasAnyPermission(['settings.manage_staff', 'patients.read']), isTrue);
    });

    test('matrix grants owner settings and denies doctor staff settings', () {
      final owner = PermissionService(
        sampleAuthSessionContext(role: StaffRole.owner, permissions: {'settings.manage_staff'}),
      );
      final doctor = PermissionService(
        sampleAuthSessionContext(role: StaffRole.doctor, permissions: {'patients.view'}),
      );

      expect(owner.hasPermission('settings.manage_staff'), isTrue);
      expect(doctor.hasPermission('settings.manage_staff'), isFalse);
      expect(doctor.hasPermission('patients.view'), isTrue);
    });
  });
}
