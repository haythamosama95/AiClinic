import 'package:ai_clinic/core/auth/permission_service.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/auth_test_support.dart';

void main() {
  group('Visit permission helpers', () {
    test('clinical detail requires create or edit_soap', () {
      final none = PermissionService(sampleAuthSessionContext(permissions: {PermissionKeys.patientsView}));
      expect(none.canViewVisitClinicalDetail(), isFalse);

      final create = PermissionService(sampleAuthSessionContext(permissions: {PermissionKeys.visitsCreate}));
      expect(create.canViewVisitClinicalDetail(), isTrue);

      final edit = PermissionService(sampleAuthSessionContext(permissions: {PermissionKeys.visitsEditSoap}));
      expect(edit.canViewVisitClinicalDetail(), isTrue);
    });

    test('upload allowed via upload key or clinical keys', () {
      final lab = PermissionService(sampleAuthSessionContext(permissions: {PermissionKeys.visitsUploadAttachment}));
      expect(lab.canUploadVisitAttachments(), isTrue);
      expect(lab.canCreateVisits(), isFalse);

      final doctor = PermissionService(
        sampleAuthSessionContext(permissions: {PermissionKeys.visitsCreate, PermissionKeys.visitsEditSoap}),
      );
      expect(doctor.canUploadVisitAttachments(), isTrue);

      final reception = PermissionService(sampleAuthSessionContext(permissions: {PermissionKeys.patientsView}));
      expect(reception.canUploadVisitAttachments(), isFalse);
    });

    test('RolePermissionSeed grants lab upload only', () {
      expect(RolePermissionSeed.labStaff, contains(PermissionKeys.visitsUploadAttachment));
      expect(RolePermissionSeed.labStaff, isNot(contains(PermissionKeys.visitsCreate)));
      expect(RolePermissionSeed.doctor, contains(PermissionKeys.visitsCreate));
    });
  });
}
