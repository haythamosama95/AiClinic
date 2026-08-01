import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/clinic-management/data/role_permissions_repository.dart';
import 'package:ai_clinic/features/clinic-management/presentation/components/roles_tab.dart';
import 'package:ai_clinic/features/clinic-management/presentation/providers/role_permissions_notifier.dart';

import '../../support/settings_rpc_test_client.dart';
import '../../support/settings_table_test_client.dart';
import 'clinic_management_widget_test_harness.dart';

class _RolePermissionsRpcClient extends SettingsRpcTestClient {
  _RolePermissionsRpcClient(this._tables);

  final Map<String, List<Map<String, dynamic>>> _tables;

  @override
  SupabaseQueryBuilder from(String table) => SettingsTableTestClient(_tables).from(table);
}

void main() {
  final matrixTables = {
    'roles_permissions': [
      {'role': 'administrator', 'permission_key': 'patients.view', 'is_granted': true, 'is_deleted': false},
      {'role': 'doctor', 'permission_key': 'patients.view', 'is_granted': true, 'is_deleted': false},
      {'role': 'receptionist', 'permission_key': 'patients.view', 'is_granted': false, 'is_deleted': false},
      {'role': 'lab_staff', 'permission_key': 'patients.view', 'is_granted': false, 'is_deleted': false},
    ],
  };

  testWidgets('RolesTab shows loading skeleton while permissions load', (tester) async {
    await pumpClinicMgmtWidget(
      tester,
      overrides: [
        authSessionProvider.overrideWith(() => PresetAuthSessionNotifier(clinicMgmtAdminAuth())),
        rolePermissionsProvider.overrideWith(() => LoadingRolePermissionsNotifier()),
      ],
      child: const RolesTab(),
    );
    await tester.pump();

    expect(find.byType(AppSkeleton), findsWidgets);
    expect(find.text('Roles & permissions'), findsNothing);
  });

  testWidgets('RolesTab shows permission denied for doctor role', (tester) async {
    await pumpClinicMgmtWidget(
      tester,
      overrides: [
        authSessionProvider.overrideWith(() => PresetAuthSessionNotifier(clinicMgmtDoctorAuth())),
        rolePermissionsProvider.overrideWith(RolePermissionsNotifier.new),
      ],
      child: const RolesTab(),
    );
    await settleClinicMgmtWidget(tester);

    expect(find.text('Permission denied'), findsOneWidget);
    expect(
      find.text('You do not have access to view or edit role permissions.'),
      findsOneWidget,
    );
  });

  testWidgets('RolesTab admin sees matrix with Save and Discard actions', (tester) async {
    final matrix = clinicMgmtSamplePermissionMatrix();
    final state = RolePermissionsUiState(
      savedMatrix: matrix,
      workingMatrix: matrix,
      editable: true,
    );

    await pumpClinicMgmtWidget(
      tester,
      overrides: [
        authSessionProvider.overrideWith(() => PresetAuthSessionNotifier(clinicMgmtAdminAuth())),
        rolePermissionsProvider.overrideWith(() => PresetRolePermissionsNotifier(state)),
      ],
      child: const RolesTab(),
    );
    await settleClinicMgmtWidget(tester);

    expect(find.text('Roles & permissions'), findsOneWidget);
    expect(find.text('Save changes'), findsOneWidget);
    expect(find.text('View'), findsOneWidget);
    expect(find.text('Discard'), findsNothing);
  });

  testWidgets('RolesTab toggle grant enables Save and Discard reverts', (tester) async {
    await pumpClinicMgmtWidget(
      tester,
      overrides: [
        authSessionProvider.overrideWith(() => PresetAuthSessionNotifier(clinicMgmtAdminAuth())),
        rolePermissionsRepositoryProvider.overrideWithValue(
          RolePermissionsRepositoryImpl(_RolePermissionsRpcClient(matrixTables)),
        ),
      ],
      child: const RolesTab(),
    );
    await settleClinicMgmtWidget(tester);

    final saveButton = find.widgetWithText(AppButton, 'Save changes');
    expect(tester.widget<AppButton>(saveButton).disabled, isTrue);

    await tester.tap(find.bySemanticsLabel('Revoke View for Doctor'));
    await settleClinicMgmtWidget(tester);

    expect(find.text('Discard'), findsOneWidget);
    expect(tester.widget<AppButton>(saveButton).disabled, isFalse);

    await tester.tap(find.text('Discard'));
    await settleClinicMgmtWidget(tester);

    expect(find.text('Discard'), findsNothing);
    expect(tester.widget<AppButton>(saveButton).disabled, isTrue);
  });
}
