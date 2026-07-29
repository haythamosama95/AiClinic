import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/ui/components/app_alert.dart';
import 'package:ai_clinic/features/auth/presentation/providers/auth_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/auth_test_support.dart';
import 'login_widget_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(installLoginImageExceptionSilencer);

  group('LoginPage structure', () {
    testWidgets('builds without exceptions in wide and narrow layouts', (tester) async {
      await pumpLoginBothLayouts(tester);
    });

    testWidgets('shows expected controls exactly once', (tester) async {
      await pumpLoginPage(tester);

      expect(loginBrandMark(), findsOneWidget);
      expect(loginUsernameField(), findsOneWidget);
      expect(loginPasswordField(), findsOneWidget);
      expect(loginSubmitButton(), findsOneWidget);
      expect(loginForgotPasswordControl(), findsOneWidget);
      expect(find.text('Welcome back'), findsOneWidget);
      expect(find.text('Enter your username'), findsOneWidget);
      expect(find.text('Enter your password'), findsOneWidget);
    });

    testWidgets('password field is obscured by default and toggles visibility', (tester) async {
      await pumpLoginPage(tester);

      expect(loginPasswordIsObscured(tester), isTrue);
      expect(loginPasswordVisibilityToggle(), findsOneWidget);

      await tester.tap(loginPasswordVisibilityToggle());
      await tester.pump();
      expect(loginPasswordIsObscured(tester), isFalse);
      expect(find.bySemanticsLabel('Hide password'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Hide password'));
      await tester.pump();
      expect(loginPasswordIsObscured(tester), isTrue);
    });
  });

  group('LoginPage auth UI states', () {
    testWidgets('idle state shows no alert banner', (tester) async {
      await pumpLoginPage(tester);

      expect(find.byType(AppAlert), findsNothing);
    });

    testWidgets('error state shows danger alert with generic sign-in failure message', (tester) async {
      await pumpLoginPage(
        tester,
        authUiState: const AuthUiState(
          errorMessage: kGenericSignInFailureMessage,
          isInfoMessage: false,
        ),
      );

      expect(find.byType(AppAlert), findsOneWidget);
      expect(find.text(kGenericSignInFailureMessage), findsOneWidget);
    });

    testWidgets('info state shows forgot-password guidance message', (tester) async {
      await pumpLoginPage(
        tester,
        authUiState: const AuthUiState(
          errorMessage: kForgotPasswordMessage,
          isInfoMessage: true,
        ),
      );

      expect(find.byType(AppAlert), findsOneWidget);
      expect(find.text(kForgotPasswordMessage), findsOneWidget);
    });

    testWidgets('submitting state disables submit button and shows loading', (tester) async {
      await pumpLoginPage(
        tester,
        authUiState: const AuthUiState(isSubmitting: true),
      );

      expect(loginSubmitButtonIsLoading(tester), isTrue);
      expect(loginSubmitButtonIsEnabled(tester), isFalse);
      expect(tester.widget<TextField>(loginUsernameField()).enabled, isTrue);
      expect(tester.widget<TextField>(loginPasswordField()).enabled, isTrue);
    });
  });

  group('LoginPage session states', () {
    testWidgets('unknown session status renders without error', (tester) async {
      final session = TestAuthSessionNotifier();
      session.setSession(AuthSessionState.initial());

      await pumpLoginPage(tester, sessionNotifier: session);

      expect(tester.takeException(), isNull);
      expect(loginSubmitButton(), findsOneWidget);
    });

    testWidgets('loading session status renders without error', (tester) async {
      final session = TestAuthSessionNotifier()..setLoading();

      await pumpLoginPage(tester, sessionNotifier: session);

      expect(tester.takeException(), isNull);
      expect(loginSubmitButton(), findsOneWidget);
    });

    testWidgets('authenticated session still renders login form (no in-widget redirect)', (tester) async {
      final session = TestAuthSessionNotifier()..setAuthenticated();

      await pumpLoginPage(tester, sessionNotifier: session);

      expect(tester.takeException(), isNull);
      expect(loginSubmitButton(), findsOneWidget);
      expect(find.text('Welcome back'), findsOneWidget);
    });

    testWidgets('does not surface authSessionProvider failure message in the UI', (tester) async {
      const failure = 'Session bootstrap failed.';
      final session = TestAuthSessionNotifier()
        ..setUnauthenticated(failureMessage: failure);

      await pumpLoginPage(tester, sessionNotifier: session);

      expect(find.text(failure), findsNothing);
      expect(find.byType(AppAlert), findsNothing);
    });
  });

  group('LoginPage testimonial carousel', () {
    testWidgets('navigation buttons exist and show one testimonial at a time', (tester) async {
      await pumpLoginPage(tester, surfaceSize: loginWideSurfaceSize);

      expect(loginCarouselNextButton(), findsOneWidget);
      expect(loginCarouselPreviousButton(), findsOneWidget);
      expect(find.text(loginFirstTestimonialName), findsOneWidget);
      expect(find.text(loginMiddleTestimonialName), findsNothing);
      expect(find.text(loginLastTestimonialName), findsNothing);
    });

    testWidgets('next and previous wrap at carousel ends', (tester) async {
      await pumpLoginPage(tester, surfaceSize: loginWideSurfaceSize);

      expect(find.text(loginFirstTestimonialName), findsOneWidget);

      await tester.tap(loginCarouselPreviousButton());
      await pumpLoginFrames(tester);
      expect(find.text(loginLastTestimonialName), findsOneWidget);
      expect(find.text(loginFirstTestimonialName), findsNothing);

      await tester.tap(loginCarouselNextButton());
      await pumpLoginFrames(tester);
      expect(find.text(loginFirstTestimonialName), findsOneWidget);

      await tester.tap(loginCarouselNextButton());
      await pumpLoginFrames(tester);
      expect(find.text(loginMiddleTestimonialName), findsOneWidget);

      await tester.tap(loginCarouselNextButton());
      await pumpLoginFrames(tester);
      expect(find.text(loginLastTestimonialName), findsOneWidget);
    });
  });
}
