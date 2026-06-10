import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/core/ui/theme/forui_app_scope.dart';
import 'package:ai_clinic/features/auth/presentation/pages/login_page.dart';
import 'package:ai_clinic/features/auth/presentation/providers/auth_notifier.dart';
import 'package:ai_clinic/features/auth/presentation/widgets/login_modal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../helpers/auth_test_support.dart';
import 'login_modal_test_support.dart';

class FakeAuthNotifier extends AuthNotifier {
  @override
  AuthUiState build() => const AuthUiState();

  @override
  Future<void> signIn({required String username, required String password}) async {
    state = state.copyWith(isSubmitting: true, clearError: true);
  }

  void completeSignInSuccess() {
    state = const AuthUiState();
  }

  void setError(String message) {
    state = AuthUiState(errorMessage: message);
  }

  void setSubmitting(bool submitting) {
    state = state.copyWith(isSubmitting: submitting);
  }
}

GoRouter _loginTestRouter({String initialLocation = AppRoutes.login}) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: AppRoutes.startupEntry,
        builder: (_, _) => const Scaffold(body: Text('Startup Entry')),
      ),
      GoRoute(path: AppRoutes.login, builder: (_, _) => const LoginPage()),
      GoRoute(
        path: AppRoutes.home,
        builder: (_, _) => const Scaffold(body: Text('Home')),
      ),
      GoRoute(
        path: AppRoutes.bootstrap,
        builder: (_, _) => const Scaffold(body: Text('Bootstrap')),
      ),
    ],
  );
}

Future<FakeAuthNotifier> pumpLoginPage(
  WidgetTester tester, {
  List<Override> extraOverrides = const [],
  String initialLocation = AppRoutes.login,
}) async {
  await tester.binding.setSurfaceSize(const Size(1280, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authNotifierProvider.overrideWith(FakeAuthNotifier.new),
        authSessionProvider.overrideWith(TestAuthSessionNotifier.new),
        ...extraOverrides,
      ],
      child: MaterialApp.router(
        theme: AppTheme.light(),
        builder: (context, child) => ForuiAppScope(child: child ?? const SizedBox.shrink()),
        routerConfig: _loginTestRouter(initialLocation: initialLocation),
      ),
    ),
  );
  await tester.pumpAndSettle();

  final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
  return container.read(authNotifierProvider.notifier) as FakeAuthNotifier;
}

void main() {
  group('LoginPage', () {
    testWidgets('renders LoginModal on the login route', (tester) async {
      await pumpLoginPage(tester);

      expect(find.byType(LoginPage), findsOneWidget);
      expect(find.byType(LoginModal), findsOneWidget);
      expect(find.text('Login'), findsWidgets);
    });

    testWidgets('displays auth notifier error message', (tester) async {
      final fakeAuth = await pumpLoginPage(tester);

      fakeAuth.setError(kGenericSignInFailureMessage);
      await tester.pumpAndSettle();

      expect(visiblePanelText('incorrect'), findsOneWidget);
    });

    testWidgets('displays session failure when not submitting', (tester) async {
      await pumpLoginPage(tester);

      final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
      (container.read(authSessionProvider.notifier) as TestAuthSessionNotifier).setUnauthenticated(
        failureMessage: kSignInUnavailableMessage,
      );
      await tester.pumpAndSettle();

      expect(visiblePanelText('Unable to sign in right now'), findsOneWidget);
    });

    testWidgets('hides session failure while submitting', (tester) async {
      final fakeAuth = await pumpLoginPage(tester);

      final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
      (container.read(authSessionProvider.notifier) as TestAuthSessionNotifier).setUnauthenticated(
        failureMessage: kSignInUnavailableMessage,
      );
      await tester.pumpAndSettle();

      fakeAuth.setSubmitting(true);
      await tester.pump();

      expect(visiblePanelText('Unable to sign in right now'), findsNothing);
    });

    testWidgets('forgot query parameter opens recovery panel on load', (tester) async {
      await pumpLoginPage(tester, initialLocation: '${AppRoutes.login}?forgot=1');

      expect(visiblePanelText('administrator-mediated'), findsOneWidget);
    });

    testWidgets('close stays on login when stack cannot pop', (tester) async {
      await pumpLoginPage(tester);

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      expect(find.byType(LoginPage), findsOneWidget);
      expect(find.byType(LoginModal), findsOneWidget);
    });

    testWidgets('close pops when login was pushed onto stack', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const parentRoute = '/parent';
      final router = GoRouter(
        initialLocation: parentRoute,
        routes: [
          GoRoute(
            path: parentRoute,
            builder: (_, _) => const Scaffold(body: Text('Parent')),
          ),
          GoRoute(path: AppRoutes.login, builder: (_, _) => const LoginPage()),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authNotifierProvider.overrideWith(FakeAuthNotifier.new),
            authSessionProvider.overrideWith(TestAuthSessionNotifier.new),
          ],
          child: MaterialApp.router(
            theme: AppTheme.light(),
            builder: (context, child) => ForuiAppScope(child: child ?? const SizedBox.shrink()),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      router.push(AppRoutes.login);
      await tester.pumpAndSettle();
      expect(find.byType(LoginModal), findsOneWidget);

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      expect(find.text('Parent'), findsOneWidget);
      expect(find.byType(LoginModal), findsNothing);
    });

    testWidgets('successful sign-in navigates to home', (tester) async {
      final fakeAuth = await pumpLoginPage(tester);

      fakeAuth.setSubmitting(true);
      await tester.pump();

      fakeAuth.completeSignInSuccess();
      await tester.pumpAndSettle();

      expect(find.text('Home'), findsOneWidget);
    });

    testWidgets('close clears displayed sign-in error', (tester) async {
      final fakeAuth = await pumpLoginPage(tester);

      fakeAuth.setError(kGenericSignInFailureMessage);
      await tester.pumpAndSettle();
      expect(visiblePanelText('incorrect'), findsOneWidget);

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      expect(find.byType(LoginPage), findsOneWidget);
      expect(visiblePanelText('incorrect'), findsNothing);
    });
  });
}
