import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/features/auth/presentation/pages/login_page.dart';
import 'package:ai_clinic/features/auth/presentation/providers/auth_notifier.dart';
import 'package:ai_clinic/core/config/supabase_config.dart';
import 'package:ai_clinic/shared/providers/auth_session_provider.dart';
import 'package:ai_clinic/shared/providers/startup_session_provider.dart';
import 'package:ai_clinic/testing/auth_test_support.dart';
import 'package:ai_clinic/testing/startup_test_support.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _StuckSubmittingAuthNotifier extends AuthNotifier {
  @override
  AuthUiState build() => const AuthUiState();

  @override
  Future<void> signIn({required String email, required String password}) async {
    state = state.copyWith(isSubmitting: true, clearError: true);
  }
}

class _LoginTestAuthNotifier extends AuthNotifier {
  bool failSignIn = false;
  int signInCalls = 0;

  @override
  AuthUiState build() => const AuthUiState();

  @override
  Future<void> signIn({required String email, required String password}) async {
    signInCalls++;
    state = state.copyWith(isSubmitting: true, clearError: true);
    if (failSignIn) {
      state = state.copyWith(isSubmitting: false, errorMessage: kGenericSignInFailureMessage);
      return;
    }

    state = const AuthUiState();
  }
}

void main() {
  setUp(() {
    SupabaseBootstrap.debugMarkReadyForTests();
  });

  tearDown(() {
    SupabaseBootstrap.debugResetForTests();
  });

  group('LoginPage', () {
    testWidgets('renders email and password fields with actions', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            startupSessionProvider.overrideWith(TestValidStartupSessionNotifier.new),
            authSessionProvider.overrideWith(TestAuthSessionNotifier.new),
          ],
          child: MaterialApp.router(
            routerConfig: GoRouter(
              routes: [
                GoRoute(path: AppRoutes.login, builder: (context, state) => const LoginPage()),
                GoRoute(
                  path: AppRoutes.forgotPassword,
                  builder: (context, state) => const Scaffold(body: Text('Forgot')),
                ),
                GoRoute(
                  path: AppRoutes.startupEntry,
                  builder: (context, state) => const Scaffold(body: Text('Startup')),
                ),
              ],
              initialLocation: AppRoutes.login,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Sign in'), findsWidgets);
      expect(find.byType(TextFormField), findsNWidgets(2));
      expect(find.text('Forgot password?'), findsOneWidget);
      expect(find.text('Back to startup'), findsOneWidget);
    });

    testWidgets('shows generic error when sign-in fails', (tester) async {
      final notifier = _LoginTestAuthNotifier()..failSignIn = true;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            startupSessionProvider.overrideWith(TestValidStartupSessionNotifier.new),
            authNotifierProvider.overrideWith(() => notifier),
            authSessionProvider.overrideWith(TestAuthSessionNotifier.new),
          ],
          child: const MaterialApp(home: LoginPage()),
        ),
      );

      await tester.enterText(find.byType(TextFormField).at(0), 'staff@clinic.test');
      await tester.enterText(find.byType(TextFormField).at(1), 'wrong-password');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();

      expect(find.text(kGenericSignInFailureMessage), findsOneWidget);
      expect(notifier.signInCalls, 1);
    });

    testWidgets('disables inputs while submitting', (tester) async {
      final notifier = _StuckSubmittingAuthNotifier();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            startupSessionProvider.overrideWith(TestValidStartupSessionNotifier.new),
            authNotifierProvider.overrideWith(() => notifier),
            authSessionProvider.overrideWith(TestAuthSessionNotifier.new),
          ],
          child: const MaterialApp(home: LoginPage()),
        ),
      );

      await tester.enterText(find.byType(TextFormField).at(0), 'staff@clinic.test');
      await tester.enterText(find.byType(TextFormField).at(1), 'password');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pump();

      expect(tester.widget<TextFormField>(find.byType(TextFormField).at(0)).enabled, isFalse);
    });
  });
}
