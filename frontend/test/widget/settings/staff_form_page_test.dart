import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/auth/domain/branch_summary.dart';
import 'package:ai_clinic/features/auth/presentation/providers/provisioning_notifier.dart';
import 'package:ai_clinic/features/settings/data/staff_admin_repository.dart';
import 'package:ai_clinic/features/settings/domain/staff_member_detail.dart';
import 'package:ai_clinic/features/settings/presentation/pages/staff_form_page.dart';
import 'package:ai_clinic/features/settings/presentation/providers/staff_form_notifier.dart';
import 'package:ai_clinic/features/settings/presentation/providers/staff_management_branches_provider.dart';
import 'package:ai_clinic/shared/providers/auth_session_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/testing/auth_test_support.dart';
import '../../support/settings_rpc_test_client.dart';

const _staffId = '00000000-0000-4000-8000-000000000101';
const _branchId = '00000000-0000-4000-8000-000000000001';

const _testBranches = [
  BranchSummary(id: _branchId, name: 'Main Branch', code: 'main'),
  BranchSummary(id: '00000000-0000-4000-8000-000000000002', name: 'North Wing', code: 'north'),
];

void main() {
  group('StaffFormPage', () {
    testWidgets('create mode shows username and password fields', (tester) async {
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();

      expect(find.text('New staff member'), findsOneWidget);
      expect(find.text('Create staff account'), findsOneWidget);
      expect(find.text('Username'), findsOneWidget);
      expect(find.text('Initial password'), findsOneWidget);
    });

    testWidgets('edit mode shows stored values with modify actions and reset password', (tester) async {
      await tester.pumpWidget(_host(staffId: _staffId));
      await tester.pumpAndSettle();

      expect(find.text('Edit staff member'), findsOneWidget);
      expect(find.text('Dr. Smith'), findsOneWidget);
      expect(find.text('Modify'), findsWidgets);
      expect(find.text('Reset password'), findsOneWidget);
      expect(find.text('Security'), findsOneWidget);
      expect(find.text('Username'), findsNothing);
    });

    testWidgets('stupid usage: empty full name blocked on create', (tester) async {
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Create staff account'));
      await tester.tap(find.text('Create staff account'));
      await tester.pumpAndSettle();

      expect(find.text('Full name is required'), findsOneWidget);
    });

    testWidgets('administrator cannot select owner when owner exists', (tester) async {
      await tester.pumpWidget(_host(role: StaffRole.administrator, ownerAlreadyExists: true));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Role'));
      await tester.pumpAndSettle();

      expect(find.text('Owner'), findsNothing);
      expect(find.text('Doctor'), findsWidgets);
    });

    testWidgets('owner can select owner role when owner already exists', (tester) async {
      await tester.pumpWidget(_host(role: StaffRole.owner, ownerAlreadyExists: true));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Role'));
      await tester.pumpAndSettle();

      expect(find.text('Owner'), findsOneWidget);
    });

    testWidgets('advanced: edit save invokes update_staff_member RPC', (tester) async {
      final rpcClient = SettingsRpcTestClient();
      await tester.pumpWidget(_host(staffId: _staffId, rpcClient: rpcClient));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();

      expect(rpcClient.lastFunction, 'update_staff_member');
      expect(rpcClient.lastParams, containsPair('p_full_name', 'Dr. Smith'));
    });

    testWidgets('corner case: missing staff shows not-found message', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authSessionProvider.overrideWith(
              () => _PresetAuthSessionNotifier(
                AuthSessionState(
                  status: AuthSessionStatus.authenticated,
                  context: sampleAuthSessionContext(permissions: {'settings.manage_staff'}),
                ),
              ),
            ),
            staffManagementBranchesProvider.overrideWith((ref) async => _testBranches),
            staffFormProvider('missing').overrideWith(() => _MissingStaffFormNotifier()),
          ],
          child: const MaterialApp(home: StaffFormPage(staffId: 'missing')),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('not found'), findsOneWidget);
    });

    testWidgets('invalid state: no permission shows denial', (tester) async {
      await tester.pumpWidget(_host(hasPermission: false));
      await tester.pumpAndSettle();

      expect(find.textContaining('do not have permission'), findsOneWidget);
    });
  });
}

Widget _host({
  String? staffId,
  bool hasPermission = true,
  StaffRole role = StaffRole.owner,
  bool ownerAlreadyExists = true,
  SettingsRpcTestClient? rpcClient,
}) {
  final staffRepo = _FakeStaffAdminRepository(
    rpcClient ?? SettingsRpcTestClient(),
    ownerAlreadyExists: ownerAlreadyExists,
    existing: staffId == null
        ? null
        : StaffMemberDetail(
            id: staffId,
            fullName: 'Dr. Smith',
            role: StaffRole.doctor,
            isActive: true,
            branchIds: const [_branchId],
            primaryBranchId: _branchId,
          ),
  );

  return ProviderScope(
    overrides: [
      authSessionProvider.overrideWith(
        () => _PresetAuthSessionNotifier(
          AuthSessionState(
            status: AuthSessionStatus.authenticated,
            context: sampleAuthSessionContext(role: role, permissions: hasPermission ? {'settings.manage_staff'} : {}),
          ),
        ),
      ),
      staffAdminRepositoryProvider.overrideWithValue(staffRepo),
      staffManagementBranchesProvider.overrideWith((ref) async => _testBranches),
      provisioningNotifierProvider.overrideWith(_TestProvisioningNotifier.new),
    ],
    child: MaterialApp(home: StaffFormPage(staffId: staffId)),
  );
}

class _PresetAuthSessionNotifier extends TestAuthSessionNotifier {
  _PresetAuthSessionNotifier(this.initial);

  final AuthSessionState initial;

  @override
  AuthSessionState build() => initial;
}

class _MissingStaffFormNotifier extends StaffFormNotifier {
  _MissingStaffFormNotifier() : super('missing');

  @override
  Future<StaffFormUiState> build() async {
    return const StaffFormUiState(
      ownerAlreadyExists: true,
      errorMessage: 'Staff member missing was not found. Return to the staff list and try again.',
    );
  }
}

class _TestProvisioningNotifier extends ProvisioningNotifier {
  @override
  ProvisioningUiState build() => const ProvisioningUiState(ownerAlreadyExists: true);
}

class _FakeStaffAdminRepository extends StaffAdminRepository {
  _FakeStaffAdminRepository(SettingsRpcTestClient client, {required this.ownerAlreadyExists, this.existing})
    : super(client);

  final bool ownerAlreadyExists;
  final StaffMemberDetail? existing;

  @override
  Future<bool> organizationHasOwner() async => ownerAlreadyExists;

  @override
  Future<StaffMemberDetail?> fetchStaffMember(String staffMemberId) async => existing;

  @override
  Future<String> updateStaffMember(UpdateStaffMemberInput input) async {
    await super.updateStaffMember(input);
    return input.staffMemberId;
  }
}
