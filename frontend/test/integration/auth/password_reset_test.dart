import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/router.dart';
import 'package:ai_clinic/core/config/supabase_config.dart';
import 'package:ai_clinic/features/auth/data/provisioning_repository.dart';
import 'package:ai_clinic/features/auth/domain/admin_reset_staff_password_result.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/auth/domain/staff_member_summary.dart';
import 'package:ai_clinic/features/auth/presentation/providers/provisioning_notifier.dart';
import 'package:ai_clinic/shared/providers/auth_session_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../support/pump_auth_app.dart';
import '../../support/settings_table_test_client.dart';
import 'package:ai_clinic/features/settings/data/staff_admin_repository.dart';
import 'package:ai_clinic/testing/auth_test_support.dart';
import 'package:ai_clinic/testing/startup_test_support.dart';

const _targetStaff = StaffMemberSummary(id: 'staff-target-1', fullName: 'Lab Tech', role: StaffRole.labStaff);

class _HarnessProvisioningRepository extends ProvisioningRepositoryImpl {
  _HarnessProvisioningRepository() : super(_FakeSupabaseClient());

  int resetCalls = 0;
  String? lastStaffId;
  String? lastPassword;

  @override
  Future<List<StaffMemberSummary>> listOrgStaffMembers() async => const [_targetStaff];

  @override
  Future<AdminResetStaffPasswordResult> resetStaffPassword({
    required String staffMemberId,
    required String newPassword,
  }) async {
    resetCalls++;
    lastStaffId = staffMemberId;
    lastPassword = newPassword;
    return AdminResetStaffPasswordResult(staffMemberId: staffMemberId, assignedPassword: newPassword);
  }
}

class _FakeSupabaseClient implements SupabaseClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  setUp(SupabaseBootstrap.debugMarkReadyForTests);
  tearDown(SupabaseBootstrap.debugResetForTests);

  testWidgets('owner reaches reset page from shell and completes reset flow', (tester) async {
    late _HarnessProvisioningRepository repo;

    final staffTable = SettingsTableTestClient({
      'staff_members': [
        {
          'id': _targetStaff.id,
          'full_name': _targetStaff.fullName,
          'role': _targetStaff.role.wireValue,
          'phone': null,
          'is_active': true,
          'is_deleted': false,
        },
      ],
    });

    await pumpAuthApp(
      tester,
      extraOverrides: [
        authSessionProvider.overrideWith(TestAuthSessionNotifier.new),
        provisioningRepositoryProvider.overrideWith((ref) => repo = _HarnessProvisioningRepository()),
        staffResetCandidatesProvider.overrideWith((ref) async => const [_targetStaff]),
        staffAdminRepositoryProvider.overrideWithValue(StaffAdminRepositoryImpl(staffTable)),
      ],
    );
    await completeStartupBootstrap(tester);

    final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
    (container.read(authSessionProvider.notifier) as TestAuthSessionNotifier).setSession(
      AuthSessionState(
        status: AuthSessionStatus.authenticated,
        context: sampleAuthSessionContext(role: StaffRole.owner, permissions: {'settings.manage_staff'}),
      ),
    );
    container.read(appRouterProvider).go(AppRoutes.staffPasswordReset);
    await tester.pumpAndSettle();

    expect(container.read(appRouterProvider).routerDelegate.currentConfiguration.uri.path, AppRoutes.settingsStaff);

    container.read(appRouterProvider).go(AppRoutes.settingsStaffResetPassword(_targetStaff.id));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), 'assigned-pass-99');
    await tester.tap(find.widgetWithText(FilledButton, 'Reset password'));
    await tester.pumpAndSettle();

    expect(repo.resetCalls, 1);
    expect(repo.lastStaffId, _targetStaff.id);
    expect(repo.lastPassword, 'assigned-pass-99');
    expect(find.textContaining('Password: assigned-pass-99'), findsOneWidget);
  });

  testWidgets('doctor cannot access reset route content', (tester) async {
    await pumpAuthApp(
      tester,
      extraOverrides: [
        authSessionProvider.overrideWith(TestAuthSessionNotifier.new),
        provisioningRepositoryProvider.overrideWith((ref) => _HarnessProvisioningRepository()),
        staffResetCandidatesProvider.overrideWith((ref) async => const [_targetStaff]),
      ],
    );
    await completeStartupBootstrap(tester);

    final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
    (container.read(authSessionProvider.notifier) as TestAuthSessionNotifier).setSession(
      AuthSessionState(
        status: AuthSessionStatus.authenticated,
        context: sampleAuthSessionContext(role: StaffRole.doctor),
      ),
    );
    container.read(appRouterProvider).go(AppRoutes.staffPasswordReset);
    await tester.pumpAndSettle();

    expect(container.read(appRouterProvider).routerDelegate.currentConfiguration.uri.path, AppRoutes.settings);
    expect(find.text('Reset password'), findsNothing);
  });

  testWidgets('forgot password from login shows no self-service and stays public', (tester) async {
    await pumpAuthApp(tester, extraOverrides: [authSessionProvider.overrideWith(TestAuthSessionNotifier.new)]);
    await completeStartupBootstrap(tester);

    final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
    container.read(appRouterProvider).go(AppRoutes.login);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();

    expect(find.textContaining('does not offer self-service'), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
    expect(container.read(authSessionProvider).isAuthenticated, isFalse);
  });

  testWidgets('unauthenticated user redirected from reset route to login', (tester) async {
    await pumpAuthApp(tester, extraOverrides: [authSessionProvider.overrideWith(TestAuthSessionNotifier.new)]);
    await completeStartupBootstrap(tester);

    final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
    container.read(appRouterProvider).go(AppRoutes.staffPasswordReset);
    await tester.pumpAndSettle();

    expect(container.read(appRouterProvider).routerDelegate.currentConfiguration.uri.path, AppRoutes.login);
  });
}
