import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/core/ui/theme/forui_app_scope.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/settings/data/staff_admin_repository.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_filter.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_item.dart';
import 'package:ai_clinic/features/settings/domain/staff_member_detail.dart';
import 'package:ai_clinic/features/settings/presentation/widgets/staff_detail_sheet.dart';
import 'package:ai_clinic/features/setup/domain/branch_summary.dart';
import 'package:ai_clinic/features/setup/presentation/providers/staff_assignable_branches_provider.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/auth_test_support.dart';
import '../../support/settings_rpc_test_client.dart';
import '../../support/settings_table_test_client.dart';

void main() {
  const staffId = '00000000-0000-4000-8000-000000000101';
  const member = StaffListItem(
    id: staffId,
    fullName: 'Dr. Smith',
    role: StaffRole.doctor,
    isActive: true,
    phone: '(603) 555-0123',
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
        phone: '(603) 555-0123',
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
        phone: '(603) 555-0123',
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
  });
}

Widget _host({
  required StaffListItem member,
  StaffRole role = StaffRole.administrator,
  Set<String> permissions = const {'settings.manage_staff'},
  String? detailUsername,
  SettingsRpcTestClient? rpcClient,
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
  _StaffDetailFakeRepository(this._tableClient, this._rpcRepo, this.member, {this.detailUsername})
    : super(_tableClient);

  final SettingsTableTestClient _tableClient;
  final StaffAdminRepositoryImpl _rpcRepo;
  final StaffListItem member;
  final String? detailUsername;

  @override
  Future<List<StaffListItem>> listStaff({StaffListFilter filter = StaffListFilter.all}) {
    return super.listStaff(filter: filter);
  }

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
}

class _PresetAuthSessionNotifier extends TestAuthSessionNotifier {
  _PresetAuthSessionNotifier(this.initial);

  final AuthSessionState initial;

  @override
  AuthSessionState build() => initial;
}
