import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/core/ui/theme/forui_app_scope.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/settings/data/staff_admin_repository.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_filter.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_item.dart';
import 'package:ai_clinic/features/settings/domain/staff_member_detail.dart';
import 'package:ai_clinic/features/settings/domain/update_staff_member_input.dart';
import 'package:ai_clinic/features/settings/presentation/pages/staff_list_page.dart';
import 'package:ai_clinic/features/settings/presentation/widgets/staff_detail_sheet.dart';
import 'package:ai_clinic/features/setup/domain/branch_summary.dart';
import 'package:ai_clinic/features/setup/data/provisioning_repository.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/auth_test_support.dart';
import '../../support/fake_postgrest_rpc.dart';
import '../../support/settings_rpc_test_client.dart';
import '../../support/settings_table_test_client.dart';
import 'package:ai_clinic/features/setup/presentation/providers/staff_assignable_branches_provider.dart';

void main() {
  const staffId = '00000000-0000-4000-8000-000000000101';
  const member = StaffListItem(
    id: staffId,
    fullName: 'Dr. Smith',
    role: StaffRole.doctor,
    isActive: true,
    phone: '6035550123',
    username: 'drsmith',
    branches: [StaffBranchLabel(id: '00000000-0000-4000-8000-000000000201', name: 'Main Clinic', isPrimary: true)],
  );

  group('StaffDetailSheet', () {
    testWidgets('opens in view mode with edit icon and blurred credentials', (tester) async {
      await tester.pumpWidget(_host(member: member));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Edit'), findsOneWidget);
      expect(find.text('Login credentials'), findsOneWidget);
      expect(find.text('Username'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
      expect(find.text('drsmith'), findsOneWidget);
      expect(find.byTooltip('Reveal Username'), findsOneWidget);
    });

    testWidgets('admin can reveal username', (tester) async {
      await tester.pumpWidget(_host(member: member));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Reveal Username'));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Reveal Username'), findsNothing);
      expect(find.text('drsmith'), findsOneWidget);
    });

    testWidgets('non-administrator cannot reveal credentials', (tester) async {
      await tester.pumpWidget(
        _host(member: member, role: StaffRole.doctor, permissions: const {'settings.manage_staff'}),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Reveal Username'), findsNothing);
      expect(find.text('Only administrators can view credentials.'), findsWidgets);
    });

    testWidgets('edit icon switches to edit mode with prefilled username and password field', (tester) async {
      await tester.pumpWidget(_host(member: member));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Edit'));
      await tester.pumpAndSettle();

      expect(find.text('Update'), findsOneWidget);
      expect(find.widgetWithText(AppTextField, 'Username *'), findsOneWidget);
      expect(find.widgetWithText(AppTextField, 'New password'), findsOneWidget);
      expect(find.text('drsmith'), findsOneWidget);
      expect(find.text('Reset password'), findsNothing);
      expect(find.byTooltip('Edit'), findsNothing);
      expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
    });

    testWidgets('loads username from detail when list item has no username', (tester) async {
      const memberWithoutUsername = StaffListItem(
        id: staffId,
        fullName: 'Dr. Smith',
        role: StaffRole.doctor,
        isActive: true,
        phone: '6035550123',
        branches: [StaffBranchLabel(id: '00000000-0000-4000-8000-000000000201', name: 'Main Clinic', isPrimary: true)],
      );

      await tester.pumpWidget(_host(member: memberWithoutUsername, detailUsername: 'drsmith'));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Reveal Username'));
      await tester.pumpAndSettle();

      expect(find.text('drsmith'), findsOneWidget);
    });

    testWidgets('detail sheet shows lifecycle actions for active staff', (tester) async {
      await tester.pumpWidget(_host(member: member));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Deactivate staff member'), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
      expect(find.byTooltip('Activate staff member'), findsNothing);
    });

    testWidgets('detail sheet shows reactivate and delete for inactive staff', (tester) async {
      const inactiveMember = StaffListItem(
        id: staffId,
        fullName: 'Dr. Smith',
        role: StaffRole.doctor,
        isActive: false,
        phone: '6035550123',
        username: 'drsmith',
        branches: [StaffBranchLabel(id: '00000000-0000-4000-8000-000000000201', name: 'Main Clinic', isPrimary: true)],
      );

      await tester.pumpWidget(_host(member: inactiveMember));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Activate staff member'), findsOneWidget);
      expect(find.byIcon(Icons.play_circle_outline), findsOneWidget);
      expect(find.byTooltip('Delete staff member permanently'), findsOneWidget);
      expect(find.byTooltip('Deactivate staff member'), findsNothing);
    });

    testWidgets('deactivate in sheet confirms before calling RPC', (tester) async {
      final rpcClient = SettingsRpcTestClient();
      await tester.pumpWidget(_host(member: member, rpcClient: rpcClient));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Deactivate staff member'));
      await tester.pumpAndSettle();

      expect(find.text('Deactivate staff member?'), findsOneWidget);
      await tester.tap(find.widgetWithText(AppButton, 'Deactivate staff member'));
      await tester.pumpAndSettle();

      expect(rpcClient.lastFunction, 'set_staff_active');
      expect(rpcClient.lastParams, containsPair('p_is_active', false));
    });

    testWidgets('last administrator deactivation shows error toast', (tester) async {
      final rpcClient = SettingsRpcTestClient(
        rpcResults: {
          'set_staff_active': {
            'success': false,
            'error_code': 'LAST_ADMINISTRATOR',
            'error_message': 'Cannot deactivate the last active administrator.',
          },
        },
      );
      await tester.pumpWidget(_host(member: member, rpcClient: rpcClient));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Deactivate staff member'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(AppButton, 'Deactivate staff member'));
      await tester.pumpAndSettle();

      expect(find.textContaining('last active administrator'), findsOneWidget);
    });

    testWidgets('update saves staff member via RPC', (tester) async {
      final rpcClient = SettingsRpcTestClient();
      await tester.pumpWidget(_host(member: member, rpcClient: rpcClient));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Edit'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(AppTextField, 'Full name *'), 'Dr. Updated');
      await tester.tap(find.widgetWithText(AppButton, 'Update'));
      await tester.pumpAndSettle();

      expect(rpcClient.lastFunction, 'update_staff_member');
      expect(rpcClient.lastParams, containsPair('p_full_name', 'Dr. Updated'));
      expect(find.text('Update'), findsNothing);
      expect(find.byTooltip('Edit'), findsOneWidget);
    });

    testWidgets('update with new password calls reset RPC', (tester) async {
      final settingsRpc = SettingsRpcTestClient();
      final provisioningRpc = RpcCaptureSupabaseClient();
      await tester.pumpWidget(_host(member: member, rpcClient: settingsRpc, provisioningClient: provisioningRpc));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Edit'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(AppTextField, 'New password'), 'NewSecret1');
      await tester.tap(find.widgetWithText(AppButton, 'Update'));
      await tester.pumpAndSettle();

      expect(settingsRpc.rpcCalls.any((call) => call.function == 'update_staff_member'), isTrue);
      expect(provisioningRpc.lastFunction, 'admin_reset_staff_password');
    });

    testWidgets('reset password button in view mode for admin', (tester) async {
      await tester.pumpWidget(_host(member: member));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(AppButton, 'Reset password'), findsOneWidget);
      expect(find.textContaining('Use Reset password below'), findsOneWidget);
    });

    testWidgets('reset password confirms and calls RPC', (tester) async {
      final provisioningRpc = RpcCaptureSupabaseClient();
      await tester.pumpWidget(_host(member: member, provisioningClient: provisioningRpc));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.widgetWithText(AppButton, 'Reset password'));
      await tester.tap(find.widgetWithText(AppButton, 'Reset password'));
      await tester.pumpAndSettle();

      expect(find.text('Reset password?'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), 'NewSecret1');
      await tester.tap(find.text('Reset password').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(provisioningRpc.lastFunction, 'admin_reset_staff_password');
      expect(provisioningRpc.lastParams, containsPair('p_new_password', 'NewSecret1'));
    });

    testWidgets('permanent delete confirms before RPC for inactive staff', (tester) async {
      const inactiveMember = StaffListItem(
        id: staffId,
        fullName: 'Dr. Smith',
        role: StaffRole.doctor,
        isActive: false,
        phone: '6035550123',
        username: 'drsmith',
        branches: [StaffBranchLabel(id: '00000000-0000-4000-8000-000000000201', name: 'Main Clinic', isPrimary: true)],
      );

      final rpcClient = SettingsRpcTestClient();
      await tester.pumpWidget(_host(member: inactiveMember, rpcClient: rpcClient));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Delete staff member permanently'));
      await tester.pumpAndSettle();

      expect(find.text('Delete staff member permanently?'), findsOneWidget);
      await tester.tap(find.widgetWithText(AppButton, 'Delete staff member'));
      await tester.pumpAndSettle();

      expect(rpcClient.lastFunction, 'delete_staff_member');
      expect(rpcClient.lastParams, containsPair('p_staff_member_id', staffId));
    });

    testWidgets('delete success closes sheet and removes card from list', (tester) async {
      const inactiveMember = StaffListItem(
        id: staffId,
        fullName: 'Dr. Smith',
        role: StaffRole.doctor,
        isActive: false,
        phone: '6035550123',
        username: 'drsmith',
        branches: [StaffBranchLabel(id: '00000000-0000-4000-8000-000000000201', name: 'Main Clinic', isPrimary: true)],
      );

      final rpcClient = SettingsRpcTestClient();
      await tester.pumpWidget(_listHost(member: inactiveMember, rpcClient: rpcClient, includeInactive: true));
      await tester.pumpAndSettle();

      expect(find.text('Dr. Smith'), findsOneWidget);
      await tester.tap(find.text('Dr. Smith'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Delete staff member permanently'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(AppButton, 'Delete staff member'));
      await tester.pumpAndSettle();

      expect(rpcClient.lastFunction, 'delete_staff_member');
      expect(find.text('Login credentials'), findsNothing);
      expect(find.text('Dr. Smith'), findsNothing);
    });

    testWidgets('window resize during staff sheet open keeps sheet usable', (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_host(member: member));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.binding.setSurfaceSize(const Size(1200, 900));
      await tester.pumpAndSettle();

      final sheet = tester.renderObject<RenderBox>(
        find.ancestor(of: find.text('Login credentials'), matching: find.byType(SizedBox)).first,
      );
      final screen = tester.renderObject<RenderBox>(find.byType(MaterialApp));
      expect(sheet.size.width, 520);
      expect(sheet.size.height, lessThanOrEqualTo(screen.size.height));
      expect(find.text('Login credentials'), findsOneWidget);
    });

    testWidgets('sheet opens from right at 520px width', (tester) async {
      await tester.pumpWidget(_host(member: member));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      final sheet = find.ancestor(of: find.text('Login credentials'), matching: find.byType(SizedBox)).first;
      final sizedBox = tester.widget<SizedBox>(sheet);
      expect(sizedBox.width, 520);
    });

    testWidgets('cancel edit restores view mode', (tester) async {
      await tester.pumpWidget(_host(member: member));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Edit'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(AppTextField, 'Full name *'), 'Changed Name');
      await tester.tap(find.widgetWithText(AppButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Edit'), findsOneWidget);
      expect(find.text('Update'), findsNothing);
      expect(find.text('Dr. Smith'), findsWidgets);
    });

    testWidgets('view mode shows reset password guidance without edit-only button', (tester) async {
      await tester.pumpWidget(_host(member: member));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(AppButton, 'Reset password'), findsOneWidget);
      expect(find.textContaining('Use Reset password below'), findsOneWidget);
    });

    testWidgets('sheet closes on Close tooltip', (tester) async {
      await tester.pumpWidget(_host(member: member));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      expect(find.text('Login credentials'), findsNothing);
    });

    testWidgets('edit while deactivate in flight disables buttons', (tester) async {
      final rpcClient = SettingsRpcTestClient();
      await tester.pumpWidget(_host(member: member, rpcClient: rpcClient));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Deactivate staff member'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(AppButton, 'Deactivate staff member'), findsOneWidget);
      expect(find.byTooltip('Edit'), findsOneWidget);
    });
  });
}

Widget _listHost({required StaffListItem member, bool includeInactive = false, SettingsRpcTestClient? rpcClient}) {
  final staff = [
    {
      'id': member.id,
      'full_name': member.fullName,
      'role': member.role.wireValue,
      'phone': member.phone,
      'is_active': member.isActive,
      'is_deleted': false,
    },
  ];

  final tableClient = SettingsTableTestClient({'staff_members': staff});
  final rpcRepo = StaffAdminRepositoryImpl(rpcClient ?? SettingsRpcTestClient());

  return ProviderScope(
    overrides: [
      authSessionProvider.overrideWith(
        () => _PresetAuthSessionNotifier(
          AuthSessionState(
            status: AuthSessionStatus.authenticated,
            context: sampleAuthSessionContext(role: StaffRole.administrator, permissions: {'settings.manage_staff'}),
          ),
        ),
      ),
      staffAdminRepositoryProvider.overrideWithValue(_DeletableStaffRepository(tableClient, rpcRepo, member)),
      staffAssignableBranchesProvider.overrideWith(
        (ref) async => const [BranchSummary(id: '00000000-0000-4000-8000-000000000201', name: 'Main Clinic')],
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      builder: (context, child) => ForuiAppScope(child: child ?? const SizedBox.shrink()),
      home: StaffListPage(embedded: true),
    ),
  );
}

class _DeletableStaffRepository extends StaffAdminRepositoryImpl {
  _DeletableStaffRepository(super.tableClient, this._rpcRepo, this.member);

  final StaffAdminRepositoryImpl _rpcRepo;
  final StaffListItem member;
  var _deleted = false;

  @override
  Future<List<StaffListItem>> listStaff({StaffListFilter filter = StaffListFilter.all}) async {
    if (_deleted) {
      return [];
    }
    return [member.copyWith(branches: member.branches, username: member.username)];
  }

  @override
  Future<StaffMemberDetail?> fetchStaffMember(String staffMemberId) async {
    if (_deleted || staffMemberId != member.id) {
      return null;
    }
    return StaffMemberDetail(
      id: member.id,
      fullName: member.fullName,
      role: member.role,
      isActive: member.isActive,
      phone: member.phone,
      username: member.username,
      branchIds: [
        for (final branch in member.branches)
          if (branch.id != null) branch.id!,
      ],
      primaryBranchId: member.branches.where((branch) => branch.isPrimary).map((branch) => branch.id).firstOrNull,
    );
  }

  @override
  Future<RpcResult> deleteStaffMember({required String staffMemberId}) async {
    final result = await _rpcRepo.deleteStaffMember(staffMemberId: staffMemberId);
    if (result.success) {
      _deleted = true;
    }
    return result;
  }
}

Widget _host({
  required StaffListItem member,
  StaffRole role = StaffRole.administrator,
  Set<String> permissions = const {'settings.manage_staff'},
  String? detailUsername,
  SettingsRpcTestClient? rpcClient,
  RpcCaptureSupabaseClient? provisioningClient,
}) {
  final tableClient = SettingsTableTestClient({
    'staff_members': [
      {
        'id': member.id,
        'full_name': member.fullName,
        'role': member.role.wireValue,
        'phone': member.phone,
        'is_active': member.isActive,
        'is_deleted': false,
        'staff_branch_assignments': [
          for (final branch in member.branches)
            {'branch_id': branch.id, 'is_primary': branch.isPrimary, 'is_deleted': false},
        ],
      },
    ],
  });

  final rpcRepo = StaffAdminRepositoryImpl(rpcClient ?? SettingsRpcTestClient());

  return ProviderScope(
    overrides: [
      authSessionProvider.overrideWith(
        () => _PresetAuthSessionNotifier(
          AuthSessionState(
            status: AuthSessionStatus.authenticated,
            context: sampleAuthSessionContext(role: role, permissions: permissions),
          ),
        ),
      ),
      staffAdminRepositoryProvider.overrideWithValue(
        _StaffDetailFakeRepository(tableClient, rpcRepo, member, detailUsername: detailUsername ?? member.username),
      ),
      provisioningRepositoryProvider.overrideWithValue(
        ProvisioningRepositoryImpl(provisioningClient ?? RpcCaptureSupabaseClient()),
      ),
      staffAssignableBranchesProvider.overrideWith(
        (ref) async => const [BranchSummary(id: '00000000-0000-4000-8000-000000000201', name: 'Main Clinic')],
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      builder: (context, child) => ForuiAppScope(child: child ?? const SizedBox.shrink()),
      home: Scaffold(
        body: Builder(
          builder: (context) {
            return Center(
              child: AppButton(label: 'Open', onPressed: () => StaffDetailSheet.show(context, member)),
            );
          },
        ),
      ),
    ),
  );
}

class _StaffDetailFakeRepository extends StaffAdminRepositoryImpl {
  _StaffDetailFakeRepository(super.tableClient, this._rpcRepo, this.member, {this.detailUsername});

  final StaffAdminRepositoryImpl _rpcRepo;
  final StaffListItem member;
  final String? detailUsername;

  @override
  Future<StaffMemberDetail?> fetchStaffMember(String staffMemberId) async {
    if (staffMemberId != member.id) {
      return null;
    }
    return StaffMemberDetail(
      id: member.id,
      fullName: member.fullName,
      role: member.role,
      isActive: member.isActive,
      phone: member.phone,
      username: detailUsername,
      branchIds: [
        for (final branch in member.branches)
          if (branch.id != null) branch.id!,
      ],
      primaryBranchId: member.branches.where((branch) => branch.isPrimary).map((branch) => branch.id).firstOrNull,
    );
  }

  @override
  Future<RpcResult> setStaffActive({required String staffMemberId, required bool isActive}) {
    return _rpcRepo.setStaffActive(staffMemberId: staffMemberId, isActive: isActive);
  }

  @override
  Future<RpcResult> deleteStaffMember({required String staffMemberId}) {
    return _rpcRepo.deleteStaffMember(staffMemberId: staffMemberId);
  }

  @override
  Future<String> updateStaffMember(UpdateStaffMemberInput input) {
    return _rpcRepo.updateStaffMember(input);
  }
}

class _PresetAuthSessionNotifier extends TestAuthSessionNotifier {
  _PresetAuthSessionNotifier(this.initial);

  final AuthSessionState initial;

  @override
  AuthSessionState build() => initial;
}
