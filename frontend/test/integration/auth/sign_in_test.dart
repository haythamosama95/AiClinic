import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/router.dart';
import 'package:ai_clinic/features/auth/data/auth_repository.dart';
import 'package:ai_clinic/features/auth/presentation/providers/auth_notifier.dart';
import 'package:ai_clinic/shared/providers/auth_session_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../support/pump_auth_app.dart';
import 'package:ai_clinic/testing/auth_test_support.dart';
import 'package:ai_clinic/testing/startup_test_support.dart';

class _SignInHarnessAuthRepository extends AuthRepository {
  _SignInHarnessAuthRepository(this._onSignIn) : super(_UninitializedSupabaseClient());

  final void Function() _onSignIn;

  @override
  Future<void> signIn({required String username, required String password}) async {
    _onSignIn();
  }

  @override
  Stream<AuthState> get authStateChanges => const Stream.empty();

  @override
  Session? get currentSession => null;
}

class _UninitializedSupabaseClient implements SupabaseClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  testWidgets('valid sign-in reaches authenticated home shell', (tester) async {
    await pumpAuthApp(
      tester,
      extraOverrides: [
        authSessionProvider.overrideWith(TestAuthSessionNotifier.new),
        authRepositoryProvider.overrideWith((ref) {
          final sessionNotifier = ref.read(authSessionProvider.notifier) as TestAuthSessionNotifier;
          return _SignInHarnessAuthRepository(sessionNotifier.setAuthenticated);
        }),
      ],
    );
    await completeStartupBootstrap(tester);

    final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
    container.read(appRouterProvider).go(AppRoutes.login);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'admin');
    await tester.enterText(find.byType(TextFormField).at(1), 'bootstrap-password');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Welcome, Test Staff'), findsOneWidget);
    expect(container.read(appRouterProvider).routerDelegate.currentConfiguration.uri.path, AppRoutes.home);
  });

  testWidgets('invalid sign-in shows generic error and stays on login', (tester) async {
    await pumpAuthApp(
      tester,
      extraOverrides: [
        authSessionProvider.overrideWith(TestAuthSessionNotifier.new),
        authRepositoryProvider.overrideWith((ref) {
          return _SignInHarnessAuthRepository(() {
            throw const AuthException('Invalid login credentials');
          });
        }),
      ],
    );
    await completeStartupBootstrap(tester);

    final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
    container.read(appRouterProvider).go(AppRoutes.login);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'staff1');
    await tester.enterText(find.byType(TextFormField).at(1), 'wrong');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    expect(find.text(kGenericSignInFailureMessage), findsOneWidget);
    expect(container.read(appRouterProvider).routerDelegate.currentConfiguration.uri.path, AppRoutes.login);
  });
}
