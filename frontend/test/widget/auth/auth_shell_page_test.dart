import 'package:ai_clinic/core/auth/permission_denied_handler.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/auth/domain/branch_summary.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:ai_clinic/features/auth/presentation/pages/auth_shell_page.dart';
import 'package:ai_clinic/features/auth/presentation/providers/auth_notifier.dart';
import 'package:ai_clinic/features/auth/presentation/providers/staff_assignable_branches_provider.dart';
import 'package:ai_clinic/shared/providers/auth_session_provider.dart';
import 'package:ai_clinic/testing/auth_test_support.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

const _branchAId = 'branch-a';
const _branchBId = 'branch-b';
const _branchA = BranchSummary(id: _branchAId, name: 'Downtown');
const _branchB = BranchSummary(id: _branchBId, name: 'Uptown');

List<Override> _shellOverrides(
  AuthSessionNotifier notifier, {
  List<BranchSummary> branches = const [_branchA, _branchB],
}) => [
  authSessionProvider.overrideWith(() => notifier),
  staffAssignableBranchesProvider.overrideWith((ref) async => branches),
];

class _AuthNotifierSignOutHarness extends AuthNotifier {
  int signOutCalls = 0;

  @override
  Future<void> signOut() async {
    signOutCalls++;
    (ref.read(authSessionProvider.notifier) as TestAuthSessionNotifier).setUnauthenticated();
  }
}

class _BranchTrackingNotifier extends TestAuthSessionNotifier {
  @override
  AuthSessionState build() => AuthSessionState(
    status: AuthSessionStatus.authenticated,
    context: sampleAuthSessionContext(
      branchIds: const [_branchAId, _branchBId],
      activeBranchId: _branchAId,
      permissions: RolePermissionSeed.owner,
    ),
  );
}

class _NoBranchNotifier extends TestAuthSessionNotifier {
  @override
  AuthSessionState build() => AuthSessionState(
    status: AuthSessionStatus.authenticated,
    context: sampleAuthSessionContext(branchIds: [], permissions: RolePermissionSeed.owner),
  );
}

class _ReceptionistShellNotifier extends TestAuthSessionNotifier {
  @override
  AuthSessionState build() => AuthSessionState(
    status: AuthSessionStatus.authenticated,
    context: sampleAuthSessionContext(
      role: StaffRole.receptionist,
      branchIds: const [_branchAId],
      activeBranchId: _branchAId,
      permissions: RolePermissionSeed.receptionist,
    ),
  );
}

class _OwnerShellNotifier extends TestAuthSessionNotifier {
  @override
  AuthSessionState build() => AuthSessionState(
    status: AuthSessionStatus.authenticated,
    context: sampleAuthSessionContext(
      branchIds: const [_branchAId],
      activeBranchId: _branchAId,
      permissions: RolePermissionSeed.owner,
    ),
  );
}

class _DoctorShellNotifier extends TestAuthSessionNotifier {
  @override
  AuthSessionState build() => AuthSessionState(
    status: AuthSessionStatus.authenticated,
    context: sampleAuthSessionContext(role: StaffRole.doctor, permissions: RolePermissionSeed.doctor),
  );
}

class _NoPatientViewShellNotifier extends TestAuthSessionNotifier {
  @override
  AuthSessionState build() => AuthSessionState(
    status: AuthSessionStatus.authenticated,
    context: sampleAuthSessionContext(
      role: StaffRole.doctor,
      branchIds: const [_branchAId],
      activeBranchId: _branchAId,
      permissions: const {PermissionKeys.aiAccess},
    ),
  );
}

void main() {
  testWidgets('shows loading copy when context is null', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authSessionProvider.overrideWith(TestAuthSessionNotifier.new)],
        child: const MaterialApp(home: AuthShellPage()),
      ),
    );

    expect(find.textContaining('Loading session context'), findsOneWidget);
  });

  testWidgets('sign out button invokes auth notifier', (tester) async {
    final harness = _AuthNotifierSignOutHarness();
    final session = TestAuthSessionNotifier();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._shellOverrides(session, branches: [_branchA]),
          authNotifierProvider.overrideWith(() => harness),
        ],
        child: const MaterialApp(home: AuthShellPage()),
      ),
    );

    session.setAuthenticated();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sign out'));
    await tester.pump();

    expect(harness.signOutCalls, 1);
  });

  testWidgets('home screen does not show reset staff password action', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authSessionProvider.overrideWith(_OwnerShellNotifier.new)],
        child: const MaterialApp(home: AuthShellPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Reset staff password'), findsNothing);
  });

  testWidgets('no branch assignment shows blocked panel with administrator guidance', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authSessionProvider.overrideWith(_NoBranchNotifier.new)],
        child: const MaterialApp(home: AuthShellPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No branch assigned'), findsOneWidget);
    expect(find.textContaining('Contact your clinic administrator'), findsOneWidget);
    expect(find.text('Permission demo'), findsNothing);
    expect(find.text('Create staff account'), findsNothing);
  });

  testWidgets('welcome shows role and active branch name', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionProvider.overrideWith(_ReceptionistShellNotifier.new),
          staffAssignableBranchesProvider.overrideWith((ref) async => [_branchA]),
        ],
        child: const MaterialApp(home: AuthShellPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Welcome, Test Staff'), findsOneWidget);
    expect(find.textContaining('Role: receptionist'), findsOneWidget);
    expect(find.textContaining('Active branch: Downtown'), findsOneWidget);
    expect(find.textContaining('Test Staff · receptionist'), findsOneWidget);
  });

  testWidgets('single branch shows label in status bar instead of dropdown', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionProvider.overrideWith(_OwnerShellNotifier.new),
          staffAssignableBranchesProvider.overrideWith((ref) async => [_branchA]),
        ],
        child: const MaterialApp(home: AuthShellPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(DropdownButton<String>), findsNothing);
    expect(find.text('Downtown'), findsWidgets);
  });

  testWidgets('status bar branch selector updates active branch in session', (tester) async {
    final notifier = _BranchTrackingNotifier();

    await tester.pumpWidget(
      ProviderScope(
        overrides: _shellOverrides(notifier),
        child: const MaterialApp(home: AuthShellPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(notifier.state.context?.activeBranchId, _branchAId);

    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Uptown').last);
    await tester.pumpAndSettle();

    expect(notifier.state.context?.activeBranchId, _branchBId);
    expect(find.textContaining('Active branch: Uptown'), findsOneWidget);
  });

  testWidgets('patient navigation visible only when granted', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionProvider.overrideWith(_OwnerShellNotifier.new),
          staffAssignableBranchesProvider.overrideWith((ref) async => [_branchA]),
        ],
        child: const MaterialApp(home: AuthShellPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Patients'), findsOneWidget);
    expect(find.text('Register patient'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionProvider.overrideWith(_NoPatientViewShellNotifier.new),
          staffAssignableBranchesProvider.overrideWith((ref) async => [_branchA]),
        ],
        child: const MaterialApp(home: AuthShellPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Patients'), findsNothing);
    expect(find.text('Register patient'), findsNothing);
  });

  testWidgets('receptionist sees patients list entry but not register shortcut', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionProvider.overrideWith(_ReceptionistShellNotifier.new),
          staffAssignableBranchesProvider.overrideWith((ref) async => [_branchA]),
        ],
        child: const MaterialApp(home: AuthShellPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Patients'), findsOneWidget);
    expect(find.text('Register patient'), findsNothing);
  });

  testWidgets('owner sees manage staff demo button; doctor does not', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionProvider.overrideWith(_OwnerShellNotifier.new),
          staffAssignableBranchesProvider.overrideWith((ref) async => [_branchA]),
        ],
        child: const MaterialApp(home: AuthShellPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Manage staff (granted)'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionProvider.overrideWith(_DoctorShellNotifier.new),
          staffAssignableBranchesProvider.overrideWith((ref) async => [_branchA]),
        ],
        child: const MaterialApp(home: AuthShellPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Manage staff (granted)'), findsNothing);
    expect(find.text('Try staff settings (always visible)'), findsOneWidget);
  });

  testWidgets('denied demo action shows permission snackbar for doctor', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionProvider.overrideWith(_DoctorShellNotifier.new),
          staffAssignableBranchesProvider.overrideWith((ref) async => [_branchA]),
        ],
        child: const MaterialApp(home: AuthShellPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Try staff settings (always visible)'));
    await tester.tap(find.text('Try staff settings (always visible)'));
    await tester.pump();

    expect(find.text(PermissionDeniedHandler.defaultMessage), findsOneWidget);
  });

  testWidgets('granted demo action shows success snackbar for owner analytics', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionProvider.overrideWith(_OwnerShellNotifier.new),
          staffAssignableBranchesProvider.overrideWith((ref) async => [_branchA]),
        ],
        child: const MaterialApp(home: AuthShellPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('View analytics (granted)'));
    await tester.pump();

    expect(find.text('Analytics is permitted for your role.'), findsOneWidget);
  });

  testWidgets('receptionist tapping denied analytics shows denial message', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionProvider.overrideWith(_ReceptionistShellNotifier.new),
          staffAssignableBranchesProvider.overrideWith((ref) async => [_branchA]),
        ],
        child: const MaterialApp(home: AuthShellPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('View analytics (denied demo)'));
    await tester.pump();

    expect(find.text(PermissionDeniedHandler.defaultMessage), findsOneWidget);
  });

  testWidgets('setActiveBranch ignores unknown branch id (no crash)', (tester) async {
    final notifier = _BranchTrackingNotifier();

    await tester.pumpWidget(
      ProviderScope(
        overrides: _shellOverrides(notifier),
        child: const MaterialApp(home: AuthShellPage()),
      ),
    );
    await tester.pumpAndSettle();

    final before = notifier.state.context?.activeBranchId;
    notifier.setActiveBranch('00000000-0000-4000-8000-000099999999');
    await tester.pump();

    expect(notifier.state.context?.activeBranchId, before);
  });
}
