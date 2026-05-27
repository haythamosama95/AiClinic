import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/router.dart';
import 'package:ai_clinic/core/config/supabase_config.dart';
import 'package:ai_clinic/features/auth/domain/branch_summary.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:ai_clinic/features/auth/presentation/providers/staff_assignable_branches_provider.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import '../../helpers/auth_test_support.dart';
import '../../helpers/startup_test_support.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/pump_auth_app.dart';

const _branchAId = 'branch-a';
const _branchBId = 'branch-b';
const _branchA = BranchSummary(id: _branchAId, name: 'Downtown');
const _branchB = BranchSummary(id: _branchBId, name: 'Uptown');

class _MultiBranchSessionNotifier extends TestAuthSessionNotifier {
  @override
  void setAuthenticated({bool setupRequired = false}) {
    setSession(
      AuthSessionState(
        status: AuthSessionStatus.authenticated,
        context: sampleAuthSessionContext(
          branchIds: const [_branchAId, _branchBId],
          activeBranchId: _branchAId,
          permissions: RolePermissionSeed.owner,
          setupRequired: setupRequired,
        ),
      ),
    );
  }
}

class _SingleBranchSessionNotifier extends TestAuthSessionNotifier {
  @override
  void setAuthenticated({bool setupRequired = false}) {
    setSession(
      AuthSessionState(
        status: AuthSessionStatus.authenticated,
        context: sampleAuthSessionContext(
          branchIds: const [_branchAId],
          activeBranchId: _branchAId,
          permissions: RolePermissionSeed.receptionist,
          setupRequired: setupRequired,
        ),
      ),
    );
  }
}

class _NoBranchSessionNotifier extends TestAuthSessionNotifier {
  @override
  void setAuthenticated({bool setupRequired = false}) {
    setSession(
      AuthSessionState(
        status: AuthSessionStatus.authenticated,
        context: sampleAuthSessionContext(
          branchIds: [],
          permissions: RolePermissionSeed.doctor,
          setupRequired: setupRequired,
        ),
      ),
    );
  }
}

void main() {
  setUp(SupabaseBootstrap.debugMarkReadyForTests);
  tearDown(SupabaseBootstrap.debugResetForTests);

  group('branch switcher integration', () {
    testWidgets('multi-branch user switches branch in status bar without re-login', (tester) async {
      await pumpAuthApp(
        tester,
        extraOverrides: [
          authSessionProvider.overrideWith(_MultiBranchSessionNotifier.new),
          staffAssignableBranchesProvider.overrideWith((ref) async => [_branchA, _branchB]),
        ],
      );
      await completeStartupBootstrap(tester);

      final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
      final session = container.read(authSessionProvider.notifier) as _MultiBranchSessionNotifier;
      session.setAuthenticated();
      container.read(appRouterProvider).go(AppRoutes.home);
      await tester.pumpAndSettle();

      expect(session.state.context?.activeBranchId, _branchAId);
      expect(find.textContaining('Active branch: Downtown'), findsOneWidget);

      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Uptown').last);
      await tester.pumpAndSettle();

      expect(session.state.context?.activeBranchId, _branchBId);
      expect(find.textContaining('Active branch: Uptown'), findsOneWidget);
      expect(find.text('Sign out'), findsOneWidget);
    });

    testWidgets('single-branch user sees branch name only in status bar', (tester) async {
      await pumpAuthApp(
        tester,
        extraOverrides: [
          authSessionProvider.overrideWith(_SingleBranchSessionNotifier.new),
          staffAssignableBranchesProvider.overrideWith((ref) async => [_branchA]),
        ],
      );
      await completeStartupBootstrap(tester);

      final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
      (container.read(authSessionProvider.notifier) as _SingleBranchSessionNotifier).setAuthenticated();
      container.read(appRouterProvider).go(AppRoutes.home);
      await tester.pumpAndSettle();

      expect(find.text('Downtown'), findsWidgets);
      expect(find.byType(DropdownButton<String>), findsNothing);
    });

    testWidgets('no branch assignment shows blocked body and status bar No branch', (tester) async {
      await pumpAuthApp(
        tester,
        extraOverrides: [
          authSessionProvider.overrideWith(_NoBranchSessionNotifier.new),
          staffAssignableBranchesProvider.overrideWith((ref) async => []),
        ],
      );
      await completeStartupBootstrap(tester);

      final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
      (container.read(authSessionProvider.notifier) as _NoBranchSessionNotifier).setAuthenticated();
      container.read(appRouterProvider).go(AppRoutes.home);
      await tester.pumpAndSettle();

      expect(find.text('No branch assigned'), findsOneWidget);
      expect(find.text('No branch'), findsOneWidget);
      expect(find.text('Permission demo'), findsNothing);
    });
  });
}
