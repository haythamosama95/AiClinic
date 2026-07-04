import 'package:ai_clinic/core/auth/permission_service.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import '../../helpers/auth_test_support.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PermissionService service catalog', () {
    test('canViewServices and canManageServices reflect grants', () {
      final full = PermissionService(
        sampleAuthSessionContext(permissions: {PermissionKeys.servicesView, PermissionKeys.servicesManage}),
      );
      final viewOnly = PermissionService(sampleAuthSessionContext(permissions: {PermissionKeys.servicesView}));
      final none = PermissionService(sampleAuthSessionContext(permissions: {}));

      expect(full.canViewServices(), isTrue);
      expect(full.canManageServices(), isTrue);

      expect(viewOnly.canViewServices(), isTrue);
      expect(viewOnly.canManageServices(), isFalse);

      expect(none.canViewServices(), isFalse);
      expect(none.canManageServices(), isFalse);
    });

    test('administrator seed includes services.view and services.manage', () {
      final admin = PermissionService(
        sampleAuthSessionContext(role: StaffRole.administrator, permissions: RolePermissionSeed.administrator),
      );

      expect(admin.canViewServices(), isTrue);
      expect(admin.canManageServices(), isTrue);
    });

    test('receptionist seed does not include catalog management grants', () {
      final receptionist = PermissionService(
        sampleAuthSessionContext(role: StaffRole.receptionist, permissions: RolePermissionSeed.receptionist),
      );

      expect(receptionist.canViewServices(), isFalse);
      expect(receptionist.canManageServices(), isFalse);
      expect(receptionist.canCreateInvoices(), isTrue);
    });
  });
}
