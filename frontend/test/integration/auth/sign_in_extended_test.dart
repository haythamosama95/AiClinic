import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/router.dart';
import 'package:ai_clinic/core/config/supabase_config.dart';
import 'package:ai_clinic/features/auth/data/auth_repository.dart';
import 'package:ai_clinic/features/auth/presentation/providers/auth_notifier.dart';
import 'package:ai_clinic/shared/providers/auth_session_provider.dart';
import 'package:ai_clinic/testing/startup_test_support.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../support/pump_auth_app.dart';
import 'package:ai_clinic/testing/auth_test_support.dart';

class _HarnessAuthRepository extends AuthRepository {
  _HarnessAuthRepository(this._onSignIn, {this.signInCalls = 0}) : super(_FakeSupabaseClient());

  final Future<void> Function() _onSignIn;
  int signInCalls;

  @override
  Future<void> signIn({required String email, required String password}) async {
    signInCalls++;
    await _onSignIn();
  }

  @override
  Stream<AuthState> get authStateChanges => const Stream.empty();

  @override
  Session? get currentSession => null;
}

class _FakeSupabaseClient implements SupabaseClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  setUp(SupabaseBootstrap.debugMarkReadyForTests);
  tearDown(SupabaseBootstrap.debugResetForTests);

  testWidgets('stuck session after sign-in shows timeout message', (tester) async {
    await pumpAuthApp(
      tester,
      extraOverrides: [
        authSessionProvider.overrideWith(TestAuthSessionNotifier.new),
        authRepositoryProvider.overrideWith((ref) => _HarnessAuthRepository(() async {})),
      ],
    );
    await completeStartupBootstrap(tester);

    final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
    container.read(appRouterProvider).go(AppRoutes.login);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'admin@clinic.local');
    await tester.enterText(find.byType(TextFormField).at(1), 'password');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));

    expect(find.textContaining('Sign-in is taking longer than expected'), findsOneWidget);
  });

  testWidgets('network auth error shows unavailable message', (tester) async {
    await pumpAuthApp(
      tester,
      extraOverrides: [
        authSessionProvider.overrideWith(TestAuthSessionNotifier.new),
        authRepositoryProvider.overrideWith(
          (ref) => _HarnessAuthRepository(() async {
            throw const AuthException('Network error', statusCode: '503');
          }),
        ),
      ],
    );
    await completeStartupBootstrap(tester);

    final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
    container.read(appRouterProvider).go(AppRoutes.login);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'staff@clinic.test');
    await tester.enterText(find.byType(TextFormField).at(1), 'pw');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    expect(find.text(kSignInUnavailableMessage), findsOneWidget);
    expect(find.text(kGenericSignInFailureMessage), findsNothing);
  });

  testWidgets('session failure message surfaces on login', (tester) async {
    await pumpAuthApp(tester, extraOverrides: [authSessionProvider.overrideWith(TestAuthSessionNotifier.new)]);
    await completeStartupBootstrap(tester);

    final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
    final session = container.read(authSessionProvider.notifier) as TestAuthSessionNotifier;
    session.setUnauthenticated(failureMessage: 'Authenticated session is missing staff claims.');

    container.read(appRouterProvider).go(AppRoutes.login);
    await tester.pumpAndSettle();

    expect(find.textContaining('staff claims'), findsNothing);
  });

  testWidgets('authenticated user on login redirects to home', (tester) async {
    await pumpAuthApp(tester, extraOverrides: [authSessionProvider.overrideWith(TestAuthSessionNotifier.new)]);
    await completeStartupBootstrap(tester);

    final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
    (container.read(authSessionProvider.notifier) as TestAuthSessionNotifier).setAuthenticated();
    container.read(appRouterProvider).go(AppRoutes.login);
    await tester.pumpAndSettle();

    expect(container.read(appRouterProvider).routerDelegate.currentConfiguration.uri.path, AppRoutes.home);
  });

  testWidgets('setup_required user on home redirects to bootstrap stub', (tester) async {
    await pumpAuthApp(tester, extraOverrides: [authSessionProvider.overrideWith(TestAuthSessionNotifier.new)]);
    await completeStartupBootstrap(tester);

    final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
    (container.read(authSessionProvider.notifier) as TestAuthSessionNotifier).setAuthenticated(setupRequired: true);
    container.read(appRouterProvider).go(AppRoutes.home);
    await tester.pumpAndSettle();

    expect(container.read(appRouterProvider).routerDelegate.currentConfiguration.uri.path, AppRoutes.bootstrap);
    expect(find.textContaining('Organization and first-branch setup'), findsOneWidget);
  });
}
