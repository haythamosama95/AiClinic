import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:ai_clinic/features/auth/domain/branch_summary.dart';
import 'package:ai_clinic/app/widgets/shell_status_bar.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/app/providers/startup_session_provider.dart'
    show
        StartupConfigurationStatus,
        StartupCurrentView,
        StartupSessionNotifier,
        StartupSessionState,
        startupSessionProvider;
import 'package:ai_clinic/app/services/startup_health_service.dart';
import '../../helpers/auth_test_support.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _branchAId = 'branch-a';
const _branchBId = 'branch-b';
const _branchA = BranchSummary(id: _branchAId, name: 'Downtown');
const _branchB = BranchSummary(id: _branchBId, name: 'Uptown');

class _MultiBranchNotifier extends TestAuthSessionNotifier {
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

class _SingleBranchNotifier extends TestAuthSessionNotifier {
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

class _NoBranchNotifier extends TestAuthSessionNotifier {
  @override
  AuthSessionState build() => AuthSessionState(
    status: AuthSessionStatus.authenticated,
    context: sampleAuthSessionContext(branchIds: [], permissions: RolePermissionSeed.owner),
  );
}

class _StaleBranchIdsNotifier extends TestAuthSessionNotifier {
  @override
  AuthSessionState build() => AuthSessionState(
    status: AuthSessionStatus.authenticated,
    context: sampleAuthSessionContext(
      branchIds: const [_branchAId, _branchBId],
      activeBranchId: _branchAId,
      permissions: RolePermissionSeed.receptionist,
    ),
  );
}

Widget _host({
  required AuthSessionNotifier sessionNotifier,
  AsyncValue<List<BranchSummary>> branchesAsync = const AsyncData([_branchA, _branchB]),
  StartupConnectivityStatus connectivity = StartupConnectivityStatus.healthy,
}) {
  return ProviderScope(
    overrides: [
      authSessionProvider.overrideWith(() => sessionNotifier),
      startupSessionProvider.overrideWith(() => _ConnectivityStartupNotifier(connectivity)),
    ],
    child: MaterialApp(
      home: Scaffold(bottomNavigationBar: ShellStatusBar(branchesAsync: branchesAsync)),
    ),
  );
}

class _ConnectivityStartupNotifier extends StartupSessionNotifier {
  _ConnectivityStartupNotifier(this._status);

  final StartupConnectivityStatus _status;

  @override
  StartupSessionState build() => StartupSessionState(
    configurationStatus: StartupConfigurationStatus.valid,
    connectivityStatus: _status,
    currentView: StartupCurrentView.unauthenticatedEntry,
    themeMode: ThemeMode.system,
    healthResult: StartupHealthResult(status: _status, checkedAt: DateTime(2026, 5, 22), checks: const []),
  );
}

void main() {
  testWidgets('trivial: shows user name and healthy connectivity', (tester) async {
    await tester.pumpWidget(_host(sessionNotifier: _SingleBranchNotifier()));
    await tester.pumpAndSettle();

    expect(find.textContaining('Test Staff'), findsOneWidget);
    expect(find.text('Healthy'), findsOneWidget);
  });

  testWidgets('single branch shows label without dropdown', (tester) async {
    await tester.pumpWidget(
      _host(sessionNotifier: _SingleBranchNotifier(), branchesAsync: const AsyncData([_branchA])),
    );
    await tester.pumpAndSettle();

    expect(find.text('Downtown'), findsOneWidget);
    expect(find.byType(DropdownButton<String>), findsNothing);
  });

  testWidgets('multi-branch dropdown switches active branch in session', (tester) async {
    final notifier = _MultiBranchNotifier();

    await tester.pumpWidget(_host(sessionNotifier: notifier, branchesAsync: const AsyncData([_branchA, _branchB])));
    await tester.pumpAndSettle();

    expect(notifier.state.context?.activeBranchId, _branchAId);

    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Uptown').last);
    await tester.pumpAndSettle();

    expect(notifier.state.context?.activeBranchId, _branchBId);
  });

  testWidgets('advanced: preserves active branch selection after switching', (tester) async {
    final notifier = _MultiBranchNotifier();

    await tester.pumpWidget(_host(sessionNotifier: notifier, branchesAsync: const AsyncData([_branchA, _branchB])));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Uptown').last);
    await tester.pumpAndSettle();

    expect(notifier.state.context?.activeBranchId, _branchBId);
    expect(find.byType(DropdownButton<String>), findsOneWidget);
  });

  testWidgets('no JWT branch assignment shows disabled No branch control', (tester) async {
    await tester.pumpWidget(_host(sessionNotifier: _NoBranchNotifier(), branchesAsync: const AsyncData([])));
    await tester.pumpAndSettle();

    expect(find.text('No branch'), findsOneWidget);
    expect(find.byType(DropdownButton<String>), findsNothing);
  });

  testWidgets('inactive-only assignments: empty branch list shows No branch', (tester) async {
    await tester.pumpWidget(_host(sessionNotifier: _StaleBranchIdsNotifier(), branchesAsync: const AsyncData([])));
    await tester.pumpAndSettle();

    expect(find.text('No branch'), findsOneWidget);
  });

  testWidgets('stupid usage: tapping No branch opens administrator guidance dialog', (tester) async {
    await tester.pumpWidget(_host(sessionNotifier: _NoBranchNotifier(), branchesAsync: const AsyncData([])));
    await tester.pumpAndSettle();

    await tester.tap(find.text('No branch'));
    await tester.pumpAndSettle();

    expect(find.text('No branch assigned'), findsWidgets);
    expect(find.textContaining('Contact your clinic administrator'), findsOneWidget);
  });

  testWidgets('invalid state: setActiveBranch ignores unknown id', (tester) async {
    final notifier = _MultiBranchNotifier();

    await tester.pumpWidget(_host(sessionNotifier: notifier, branchesAsync: const AsyncData([_branchA, _branchB])));
    await tester.pumpAndSettle();

    notifier.setActiveBranch('00000000-0000-4000-8000-000099999999');
    await tester.pump();

    expect(notifier.state.context?.activeBranchId, _branchAId);
  });

  testWidgets('edge case: loading branches shows spinner in branch section', (tester) async {
    await tester.pumpWidget(_host(sessionNotifier: _MultiBranchNotifier(), branchesAsync: const AsyncLoading()));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('edge case: branch fetch error shows unavailable label', (tester) async {
    await tester.pumpWidget(
      _host(sessionNotifier: _MultiBranchNotifier(), branchesAsync: AsyncError(Exception('network'), StackTrace.empty)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Branch unavailable'), findsOneWidget);
  });

  testWidgets('regression: degraded connectivity surfaces Degraded label', (tester) async {
    await tester.pumpWidget(
      _host(sessionNotifier: _SingleBranchNotifier(), connectivity: StartupConnectivityStatus.degraded),
    );
    await tester.pumpAndSettle();

    expect(find.text('Degraded'), findsOneWidget);
  });

  testWidgets('regression: null session shows placeholder branch and user labels', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authSessionProvider.overrideWith(TestAuthSessionNotifier.new)],
        child: const MaterialApp(
          home: Scaffold(bottomNavigationBar: ShellStatusBar(branchesAsync: AsyncData([]))),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Branch…'), findsOneWidget);
    expect(find.text('User…'), findsOneWidget);
  });
}
