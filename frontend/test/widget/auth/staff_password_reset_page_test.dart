import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/core/config/supabase_config.dart';
import 'package:ai_clinic/features/auth/data/provisioning_repository.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/auth/domain/staff_member_summary.dart';
import 'package:ai_clinic/features/auth/presentation/pages/staff_password_reset_page.dart';
import 'package:ai_clinic/features/auth/presentation/providers/provisioning_notifier.dart';
import 'package:ai_clinic/shared/providers/auth_session_provider.dart';
import 'package:ai_clinic/testing/auth_test_support.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _OwnerNotifier extends TestAuthSessionNotifier {
  @override
  AuthSessionState build() => AuthSessionState(
    status: AuthSessionStatus.authenticated,
    context: sampleAuthSessionContext(role: StaffRole.owner),
  );
}

class _DoctorNotifier extends TestAuthSessionNotifier {
  @override
  AuthSessionState build() => AuthSessionState(
    status: AuthSessionStatus.authenticated,
    context: sampleAuthSessionContext(role: StaffRole.doctor),
  );
}

const _receptionist = StaffMemberSummary(id: 'staff-rec-1', fullName: 'Front Desk', role: StaffRole.receptionist);

class _TestProvisioningNotifier extends ProvisioningNotifier {
  _TestProvisioningNotifier({this.resetResult, this.failReset = false});

  final AdminResetStaffPasswordResult? resetResult;
  final bool failReset;
  int resetCalls = 0;

  @override
  ProvisioningUiState build() => const ProvisioningUiState();

  @override
  Future<AdminResetStaffPasswordResult?> resetStaffPassword({
    required String staffMemberId,
    required String newPassword,
  }) async {
    resetCalls++;
    if (newPassword.trim().isEmpty) {
      state = state.copyWith(errorMessage: 'Enter a new password for the staff member.');
      return null;
    }
    if (newPassword.trim().length < 6) {
      state = state.copyWith(errorMessage: 'Password must be at least 6 characters.');
      return null;
    }
    if (staffMemberId.trim().isEmpty) {
      state = state.copyWith(errorMessage: 'Select a staff member to reset.');
      return null;
    }
    if (failReset) {
      state = state.copyWith(errorMessage: 'You do not have permission to reset staff passwords.');
      return null;
    }
    return resetResult ??
        AdminResetStaffPasswordResult(staffMemberId: staffMemberId, assignedPassword: newPassword.trim());
  }
}

class _FakeProvisioningRepository extends ProvisioningRepository {
  _FakeProvisioningRepository() : super(_ThrowingClient());

  @override
  Future<List<StaffMemberSummary>> listOrgStaffMembers() async => const [_receptionist];
}

class _ThrowingClient implements SupabaseClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  setUp(SupabaseBootstrap.debugMarkReadyForTests);
  tearDown(SupabaseBootstrap.debugResetForTests);

  Future<void> pumpResetPage(
    WidgetTester tester, {
    required AuthSessionNotifier sessionNotifier,
    ProvisioningNotifier? provisioningNotifier,
  }) async {
    await tester.binding.setSurfaceSize(const Size(800, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionProvider.overrideWith(() => sessionNotifier),
          provisioningRepositoryProvider.overrideWith((ref) => _FakeProvisioningRepository()),
          staffResetCandidatesProvider.overrideWith((ref) async => const [_receptionist]),
          if (provisioningNotifier != null) provisioningNotifierProvider.overrideWith(() => provisioningNotifier),
        ],
        child: MaterialApp(home: const StaffPasswordResetPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('doctor sees permission denied without form fields', (tester) async {
    await pumpResetPage(tester, sessionNotifier: _DoctorNotifier());

    expect(find.textContaining('Only clinic owners and administrators'), findsOneWidget);
    expect(find.text('Reset password'), findsNothing);
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
  });

  testWidgets('owner sees staff picker and password field', (tester) async {
    await pumpResetPage(tester, sessionNotifier: _OwnerNotifier());

    expect(find.text('Staff member'), findsOneWidget);
    expect(find.text('New password'), findsOneWidget);
    expect(find.text('Reset password'), findsOneWidget);
  });

  testWidgets('stupid user submits empty password shows validation', (tester) async {
    final notifier = _TestProvisioningNotifier();
    await pumpResetPage(tester, sessionNotifier: _OwnerNotifier(), provisioningNotifier: notifier);

    await tester.tap(find.text('Reset password'));
    await tester.pump();

    expect(notifier.resetCalls, 0);
    expect(find.text('Enter a new password'), findsOneWidget);
  });

  testWidgets('short password rejected before RPC', (tester) async {
    final notifier = _TestProvisioningNotifier();
    await pumpResetPage(tester, sessionNotifier: _OwnerNotifier(), provisioningNotifier: notifier);

    await tester.enterText(find.byType(TextFormField), 'abc');
    await tester.tap(find.text('Reset password'));
    await tester.pump();

    expect(notifier.resetCalls, 0);
    expect(find.textContaining('at least 6 characters'), findsOneWidget);
  });

  testWidgets('successful reset shows assigned password dialog', (tester) async {
    final notifier = _TestProvisioningNotifier(
      resetResult: const AdminResetStaffPasswordResult(
        staffMemberId: 'staff-rec-1',
        assignedPassword: 'new-secure-pass',
      ),
    );
    await pumpResetPage(tester, sessionNotifier: _OwnerNotifier(), provisioningNotifier: notifier);

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Front Desk (receptionist)'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), 'new-secure-pass');
    await tester.tap(find.text('Reset password'));
    await tester.pumpAndSettle();

    expect(notifier.resetCalls, 1);
    expect(find.textContaining('Share this new password'), findsOneWidget);
    expect(find.textContaining('Password: new-secure-pass'), findsOneWidget);
  });

  testWidgets('RPC failure surfaces error message', (tester) async {
    final notifier = _TestProvisioningNotifier(failReset: true);
    await pumpResetPage(tester, sessionNotifier: _OwnerNotifier(), provisioningNotifier: notifier);

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Front Desk (receptionist)'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), 'valid-password');
    await tester.tap(find.text('Reset password'));
    await tester.pumpAndSettle();

    expect(find.textContaining('permission to reset'), findsOneWidget);
  });

  testWidgets('back to home navigates when wired in router', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionProvider.overrideWith(_OwnerNotifier.new),
          provisioningRepositoryProvider.overrideWith((ref) => _FakeProvisioningRepository()),
          staffResetCandidatesProvider.overrideWith((ref) async => const [_receptionist]),
        ],
        child: MaterialApp.router(
          routerConfig: GoRouter(
            routes: [
              GoRoute(
                path: AppRoutes.home,
                builder: (context, state) => const Scaffold(body: Text('Home')),
              ),
              GoRoute(path: AppRoutes.staffPasswordReset, builder: (context, state) => const StaffPasswordResetPage()),
            ],
            initialLocation: AppRoutes.staffPasswordReset,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Back to home'));
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsOneWidget);
  });
}
