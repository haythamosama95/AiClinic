import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/router.dart';
import 'package:ai_clinic/core/config/supabase_config.dart';
import 'package:ai_clinic/features/auth/data/auth_repository.dart';
import 'package:ai_clinic/shared/providers/auth_session_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../support/pump_auth_app.dart';
import 'package:ai_clinic/testing/auth_test_support.dart';
import 'package:ai_clinic/testing/startup_test_support.dart';

class _SignOutHarnessRepository extends AuthRepository {
  _SignOutHarnessRepository() : super(_FakeClient());

  int signOutCalls = 0;

  @override
  Future<void> signOut() async {
    signOutCalls++;
  }

  @override
  Stream<AuthState> get authStateChanges => const Stream.empty();

  @override
  Session? get currentSession => null;
}

class _FakeClient implements SupabaseClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  setUp(SupabaseBootstrap.debugMarkReadyForTests);
  tearDown(SupabaseBootstrap.debugResetForTests);

  testWidgets('sign out returns to login and blocks home', (tester) async {
    late _SignOutHarnessRepository repo;

    await pumpAuthApp(
      tester,
      extraOverrides: [
        authSessionProvider.overrideWith(TestAuthSessionNotifier.new),
        authRepositoryProvider.overrideWith((ref) => repo = _SignOutHarnessRepository()),
      ],
    );
    await completeStartupBootstrap(tester);

    final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
    (container.read(authSessionProvider.notifier) as TestAuthSessionNotifier).setAuthenticated();
    container.read(appRouterProvider).go(AppRoutes.home);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();

    expect(repo.signOutCalls, greaterThanOrEqualTo(1));
    expect(container.read(authSessionProvider).isAuthenticated, isFalse);

    container.read(appRouterProvider).go(AppRoutes.home);
    await tester.pumpAndSettle();
    expect(container.read(appRouterProvider).routerDelegate.currentConfiguration.uri.path, AppRoutes.login);
  });

  testWidgets('sign out twice does not throw', (tester) async {
    await pumpAuthApp(
      tester,
      extraOverrides: [
        authSessionProvider.overrideWith(TestAuthSessionNotifier.new),
        authRepositoryProvider.overrideWith((ref) => _SignOutHarnessRepository()),
      ],
    );
    await completeStartupBootstrap(tester);

    final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
    final notifier = container.read(authSessionProvider.notifier) as TestAuthSessionNotifier;
    notifier.setAuthenticated();
    container.read(appRouterProvider).go(AppRoutes.home);
    await tester.pumpAndSettle();

    await notifier.signOut();
    await notifier.signOut();
    expect(container.read(authSessionProvider).status, AuthSessionStatus.unauthenticated);
  });
}
