import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import '../../helpers/role_permission_seed.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const allPermissionKeys = <String>[
    PermissionKeys.manageStaff,
    PermissionKeys.manageBranches,
    PermissionKeys.patientsView,
    PermissionKeys.patientsCreate,
    PermissionKeys.patientsEdit,
    PermissionKeys.patientsDelete,
    PermissionKeys.patientsReassignMrn,
    PermissionKeys.appointmentsCreate,
    PermissionKeys.appointmentsCancel,
    PermissionKeys.appointmentsRead,
    PermissionKeys.visitsCreate,
    PermissionKeys.visitsEditSoap,
    PermissionKeys.visitsUploadAttachment,
    PermissionKeys.analyticsView,
    PermissionKeys.aiAccess,
    PermissionKeys.invoicesView,
    PermissionKeys.invoicesCreate,
    PermissionKeys.invoicesApplyDiscount,
    PermissionKeys.invoicesVoid,
    PermissionKeys.paymentsRecord,
    PermissionKeys.paymentsRefund,
    PermissionKeys.insuranceManage,
    PermissionKeys.settingsBillingManage,
    PermissionKeys.shiftsManage,
    PermissionKeys.servicesView,
    PermissionKeys.servicesManage,
  ];

  final dotSeparatedSnakeCase = RegExp(r'^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$');

  group('PermissionKeys contract', () {
    test('declares no duplicate values', () {
      expect(allPermissionKeys.toSet().length, allPermissionKeys.length);
    });

    test('every value is non-empty, lowercase, and whitespace-free', () {
      for (final key in allPermissionKeys) {
        expect(key, isNotEmpty);
        expect(key, key.toLowerCase());
        expect(key.contains(RegExp(r'\s')), isFalse);
      }
    });

    test('every value matches dot-separated snake_case shape', () {
      for (final key in allPermissionKeys) {
        expect(dotSeparatedSnakeCase.hasMatch(key), isTrue, reason: key);
      }
    });

    test('pins seed-critical literal values', () {
      expect(PermissionKeys.manageStaff, 'settings.manage_staff');
      expect(PermissionKeys.patientsReassignMrn, 'patients.reassign_mrn');
      expect(PermissionKeys.invoicesVoid, 'invoices.void');
    });

    test('every RolePermissionSeed grant references a declared PermissionKeys value', () {
      final declaredValues = allPermissionKeys.toSet();
      final seedGrants = <String>{
        ...RolePermissionSeed.administrator,
        ...RolePermissionSeed.doctor,
        ...RolePermissionSeed.receptionist,
        ...RolePermissionSeed.labStaff,
      };

      for (final grant in seedGrants) {
        expect(declaredValues, contains(grant), reason: grant);
      }
    });
  });
}
