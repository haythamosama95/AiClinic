import 'package:ai_clinic/core/auth/permission_service.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/auth_test_support.dart';

void main() {
  group('PermissionService appointment methods', () {
    test('canAccessAppointments true when create granted', () {
      final service = PermissionService(sampleAuthSessionContext(permissions: {PermissionKeys.appointmentsCreate}));

      expect(service.canAccessAppointments(), isTrue);
      expect(service.canCreateAppointments(), isTrue);
      expect(service.canCancelAppointments(), isFalse);
    });

    test('canAccessAppointments true when cancel granted only', () {
      final service = PermissionService(sampleAuthSessionContext(permissions: {PermissionKeys.appointmentsCancel}));

      expect(service.canAccessAppointments(), isTrue);
      expect(service.canCreateAppointments(), isFalse);
      expect(service.canCancelAppointments(), isTrue);
    });

    test('canAccessAppointments false without either grant', () {
      final service = PermissionService(sampleAuthSessionContext(permissions: {PermissionKeys.patientsView}));

      expect(service.canAccessAppointments(), isFalse);
    });

    test('null context denies all appointment permissions', () {
      const service = PermissionService(null);

      expect(service.canAccessAppointments(), isFalse);
      expect(service.canCreateAppointments(), isFalse);
      expect(service.canCancelAppointments(), isFalse);
    });

    test('no branch assignment denies appointment access', () {
      final context = sampleAuthSessionContext(permissions: {PermissionKeys.appointmentsCreate});
      final service = PermissionService(context.copyWith(branchIds: []));

      expect(service.canAccessAppointments(), isFalse);
    });

    test('receptionist seed includes appointment grants', () {
      final service = PermissionService(sampleAuthSessionContext(permissions: RolePermissionSeed.receptionist));

      expect(service.canAccessAppointments(), isTrue);
      expect(service.canCreateAppointments(), isTrue);
      expect(service.canCancelAppointments(), isTrue);
    });
  });
}
