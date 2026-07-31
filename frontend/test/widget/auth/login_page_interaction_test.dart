import 'package:ai_clinic/app/navigation/login_query_params.dart';
import 'package:ai_clinic/features/auth/domain/staff_username.dart';
import 'package:ai_clinic/features/auth/presentation/dev/auth_dev_widgets.dart';
import 'package:ai_clinic/features/auth/presentation/providers/auth_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/auth_test_support.dart';
import 'login_widget_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(installLoginImageExceptionSilencer);

  group('LoginPage sign-in submission', () {
    testWidgets('valid credentials invoke sign-in once with entered values', (tester) async {
      final session = SignInCapturingSessionNotifier();
      final repository = RecordingAuthRepository();

      await pumpLoginPage(
        tester,
        sessionNotifier: session,
        authRepository: repository,
      );

      await enterLoginCredentials(tester, username: 'staff1', password: 'secret');
      await tapLoginSubmit(tester);
      await tester.pump();

      expect(repository.signInCallCount, 1);
      expect(repository.lastUsername, 'staff1');
      expect(repository.lastPassword, 'secret');
    });

    testWidgets('empty username shows validation message and skips repository', (tester) async {
      final repository = RecordingAuthRepository();

      await pumpLoginPage(tester, authRepository: repository);

      await enterLoginCredentials(tester, username: '', password: 'secret');
      await tapLoginSubmit(tester);

      expect(find.text('Username is required.'), findsOneWidget);
      expect(repository.signInCallCount, 0);
    });

    testWidgets('invalid username format shows validation message and skips repository', (tester) async {
      final repository = RecordingAuthRepository();

      await pumpLoginPage(tester, authRepository: repository);

      await enterLoginCredentials(tester, username: 'bad@name', password: 'secret');
      await tapLoginSubmit(tester);

      expect(find.text(validateStaffUsername('bad@name')!), findsOneWidget);
      expect(repository.signInCallCount, 0);
    });

    testWidgets('empty password shows required message and skips repository', (tester) async {
      final repository = RecordingAuthRepository();

      await pumpLoginPage(tester, authRepository: repository);

      await enterLoginCredentials(tester, username: 'staff1', password: '');
      await tapLoginSubmit(tester);

      expect(find.text('Password is required.'), findsOneWidget);
      expect(repository.signInCallCount, 0);
    });

    testWidgets('rapid second tap while submitting does not double-fire sign-in', (tester) async {
      final session = SignInCapturingSessionNotifier();
      final repository = HangingAuthRepository();

      await pumpLoginPage(
        tester,
        sessionNotifier: session,
        authRepository: repository,
      );

      await enterLoginCredentials(tester, username: 'staff1', password: 'secret');
      await tapLoginSubmit(tester);
      await tester.pump();

      expect(repository.signInCallCount, 1);
      expect(loginSubmitButtonIsLoading(tester), isTrue);

      await tester.tap(loginSubmitButton());
      await tester.pump();

      expect(repository.signInCallCount, 1);

      repository.releaseSignIn();
      await tester.pump();
    });
  });

  group('LoginPage keyboard and links', () {
    testWidgets('Enter in password field submits the form', (tester) async {
      final session = SignInCapturingSessionNotifier();
      final repository = RecordingAuthRepository();

      await pumpLoginPage(
        tester,
        sessionNotifier: session,
        authRepository: repository,
      );

      await enterLoginCredentials(tester, username: 'staff1', password: 'secret');
      await triggerPasswordFieldEnter(tester);

      expect(repository.signInCallCount, 1);
    });

    testWidgets('Enter in username field moves focus instead of submitting', (tester) async {
      final repository = RecordingAuthRepository();

      await pumpLoginPage(tester, authRepository: repository);

      await tester.enterText(loginUsernameField(), 'staff1');
      await tester.pump();
      await triggerUsernameFieldNext(tester);

      expect(repository.signInCallCount, 0);
      expect(Focus.of(tester.element(loginPasswordField())).hasFocus, isTrue);
    });

    testWidgets('forgot-password control shows info message', (tester) async {
      await pumpLoginPage(tester);

      await tester.tap(loginForgotPasswordControl());
      await tester.pump();

      expect(find.text(kForgotPasswordMessage), findsOneWidget);
    });

    testWidgets('typing in a field clears a displayed error banner', (tester) async {
      await pumpLoginPage(tester);

      await tester.tap(loginForgotPasswordControl());
      await tester.pump();
      expect(find.text(kForgotPasswordMessage), findsOneWidget);

      await tester.enterText(loginUsernameField(), 'a');
      await tester.pump();

      expect(find.text(kForgotPasswordMessage), findsNothing);
    });
  });

  group('LoginPage query parameters', () {
    testWidgets('forgot-password query intent shows info message on load', (tester) async {
      await pumpLoginRouter(
        tester,
        initialLocation: loginRouteWithForgotPasswordIntent(),
      );
      await tester.pump();

      expect(find.text(kForgotPasswordMessage), findsOneWidget);
    });

    testWidgets('plain login route shows no forgot-password info message', (tester) async {
      await pumpLoginRouter(tester);

      expect(find.text(kForgotPasswordMessage), findsNothing);
      expect(LoginQueryParams.isForgotPasswordIntent(const {}), isFalse);
    });
  });

  group('LoginPage dev panel', () {
    testWidgets('renders three dev controls in debug builds', (tester) async {
      await pumpLoginPage(tester);

      expect(find.text('Dev login (admin)'), findsOneWidget);
      expect(find.text('Fill Dummy Clinic'), findsOneWidget);
      expect(find.text('Reset Clinic'), findsOneWidget);
    });

    testWidgets('dev login as admin triggers bootstrap credential sign-in', (tester) async {
      final session = SignInCapturingSessionNotifier();
      final repository = RecordingAuthRepository();

      await pumpLoginPage(
        tester,
        sessionNotifier: session,
        authRepository: repository,
      );

      await tester.tap(find.text('Dev login (admin)'));
      await tester.pump();

      expect(repository.signInCallCount, 1);
      expect(repository.lastUsername, AuthDevBootstrapCredentials.username);
      expect(repository.lastPassword, AuthDevBootstrapCredentials.password);
    });
  });

  group('LoginPage dispose', () {
    testWidgets('navigating away while unauthenticated resets sign-in form state', (tester) async {
      await pumpLoginRouter(tester);

      readAuthNotifier(tester).showForgotPasswordMessage();
      await tester.pump();
      expect(readAuthUiState(tester).errorMessage, kForgotPasswordMessage);

      await navigateAwayFromLogin(tester);
      await tester.pump();

      expect(readAuthUiState(tester), const AuthUiState());
    });

    testWidgets('navigating away while authenticated does not reset sign-in form state', (tester) async {
      final session = TestAuthSessionNotifier()..setAuthenticated();

      await pumpLoginRouter(tester, sessionNotifier: session);

      readAuthNotifier(tester).showForgotPasswordMessage();
      await tester.pump();
      expect(readAuthUiState(tester).errorMessage, kForgotPasswordMessage);

      await navigateAwayFromLogin(tester);
      await tester.pump();

      expect(readAuthUiState(tester).errorMessage, kForgotPasswordMessage);
    });
  });
}
