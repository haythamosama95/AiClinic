import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/core/ui/theme/forui_app_scope.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/auth/presentation/providers/auth_notifier.dart';
import 'package:ai_clinic/features/auth/presentation/widgets/login_modal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

import 'login_modal_test_support.dart';

void main() {
  group('LoginModal layout', () {
    testWidgets('renders branding panel and credential form', (tester) async {
      await pumpLoginModalWidget(tester);

      expect(find.text('AI Clinic'), findsOneWidget);
      expect(find.text('Login'), findsNWidgets(2)); // heading + button
      expect(find.text('Character illustration'), findsOneWidget);
      expect(find.byType(AppTextField), findsNWidgets(2));
      expect(find.byType(AppButton), findsOneWidget);
      expect(find.text('Forgot Password?'), findsOneWidget);
      expect(find.byTooltip('Close'), findsOneWidget);
    });

    testWidgets('uses side-by-side layout on wide surfaces', (tester) async {
      await pumpLoginModalWidget(tester, size: const Size(1280, 900));

      expect(find.byType(IntrinsicHeight), findsOneWidget);
      expect(find.byType(Row), findsWidgets);
    });

    testWidgets('uses stacked layout on compact surfaces', (tester) async {
      await pumpLoginModalWidget(tester, size: const Size(600, 900));

      expect(find.byType(IntrinsicHeight), findsNothing);
      expect(find.byType(SingleChildScrollView), findsWidgets);
    });
  });

  group('LoginModal form validation', () {
    testWidgets('empty submit shows username and password required errors', (tester) async {
      await pumpLoginModalWidget(tester);

      await tester.tap(find.widgetWithText(AppButton, 'Login'));
      await tester.pumpAndSettle();

      expect(find.text('Username is required.'), findsOneWidget);
      expect(find.text('This field is required'), findsOneWidget);
    });

    testWidgets('invalid short username shows validation error', (tester) async {
      await pumpLoginModalWidget(tester);

      await tester.enterText(find.byType(AppTextField).at(0), 'ab');
      await tester.enterText(find.byType(AppTextField).at(1), 'secret');
      await tester.tap(find.widgetWithText(AppButton, 'Login'));
      await tester.pumpAndSettle();

      expect(find.text('Enter a valid username.'), findsOneWidget);
    });

    testWidgets('username containing @ shows validation error', (tester) async {
      await pumpLoginModalWidget(tester);

      await tester.enterText(find.byType(AppTextField).at(0), 'user@clinic');
      await tester.enterText(find.byType(AppTextField).at(1), 'secret');
      await tester.tap(find.widgetWithText(AppButton, 'Login'));
      await tester.pumpAndSettle();

      expect(find.text('Enter a valid username.'), findsOneWidget);
    });

    testWidgets('invalid username characters show pattern error', (tester) async {
      await pumpLoginModalWidget(tester);

      await tester.enterText(find.byType(AppTextField).at(0), 'bad user');
      await tester.enterText(find.byType(AppTextField).at(1), 'secret');
      await tester.tap(find.widgetWithText(AppButton, 'Login'));
      await tester.pumpAndSettle();

      expect(find.text('Username may use letters, numbers, underscore, and hyphen.'), findsOneWidget);
    });

    testWidgets('valid credentials invoke onSubmit with trimmed username', (tester) async {
      String? submittedUsername;
      String? submittedPassword;

      await pumpLoginModalWidget(
        tester,
        onSubmit: (username, password) {
          submittedUsername = username;
          submittedPassword = password;
        },
      );

      await tester.enterText(find.byType(AppTextField).at(0), '  Staff_One  ');
      await tester.enterText(find.byType(AppTextField).at(1), 'secret');
      await tester.tap(find.widgetWithText(AppButton, 'Login'));
      await tester.pumpAndSettle();

      expect(submittedUsername, 'Staff_One');
      expect(submittedPassword, 'secret');
    });
  });

  group('LoginModal password visibility', () {
    testWidgets('password is obscured by default', (tester) async {
      await pumpLoginModalWidget(tester);

      final passwordField = tester.widget<AppTextField>(find.byType(AppTextField).at(1));
      expect(passwordField.obscureText, isTrue);
      expect(find.byTooltip('Show password'), findsOneWidget);
    });

    testWidgets('toggle reveals password and swaps tooltip', (tester) async {
      await pumpLoginModalWidget(tester);

      await tester.tap(find.byTooltip('Show password'));
      await tester.pumpAndSettle();

      final passwordField = tester.widget<AppTextField>(find.byType(AppTextField).at(1));
      expect(passwordField.obscureText, isFalse);
      expect(find.byTooltip('Hide password'), findsOneWidget);
    });

    testWidgets('close button restores obscured password', (tester) async {
      await pumpLoginModalWidget(tester);

      await tester.tap(find.byTooltip('Show password'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      final passwordField = tester.widget<AppTextField>(find.byType(AppTextField).at(1));
      expect(passwordField.obscureText, isTrue);
    });
  });

  group('LoginModal submit and loading', () {
    testWidgets('submit hides forgot password info panel', (tester) async {
      await pumpLoginModalWidget(tester, initialShowForgotPasswordInfo: true);

      expect(visiblePanelText('administrator-mediated'), findsOneWidget);

      await tester.enterText(find.byType(AppTextField).at(0), 'staff1');
      await tester.enterText(find.byType(AppTextField).at(1), 'secret');
      await tester.tap(find.widgetWithText(AppButton, 'Login'));
      await tester.pumpAndSettle();

      expect(visiblePanelText('administrator-mediated'), findsNothing);
    });

    testWidgets('isSubmitting shows loading indicator and disables login', (tester) async {
      await pumpLoginModalWidget(tester, isSubmitting: true, settle: false);

      expect(find.byType(FCircularProgress), findsOneWidget);

      final loginButton = tester.widget<AppButton>(find.byType(AppButton));
      expect(loginButton.isLoading, isTrue);
      expect(loginButton.onPressed, isNull);
    });
  });

  group('LoginModal sign-in error panel', () {
    testWidgets('error message renders destructive alert below login button', (tester) async {
      await pumpLoginModalWidget(tester, errorMessage: kGenericSignInFailureMessage);

      expect(visiblePanelText('incorrect'), findsOneWidget);

      final loginButtonY = tester.getCenter(find.byType(AppButton)).dy;
      final errorY = tester.getTopLeft(visiblePanelText('incorrect')).dy;
      expect(errorY, greaterThan(loginButtonY));
    });

    testWidgets('error panel fades in to full opacity', (tester) async {
      String? errorMessage;

      await pumpLoginModal(
        tester,
        child: StatefulBuilder(
          builder: (context, setState) {
            return LoginModal(
              errorMessage: errorMessage,
              onSubmit: (_, _) => setState(() => errorMessage = kGenericSignInFailureMessage),
            );
          },
        ),
      );

      expect(loginStatusFadeTransition, findsNothing);

      await tester.enterText(find.byType(AppTextField).at(0), 'staff1');
      await tester.enterText(find.byType(AppTextField).at(1), 'secret');
      await tester.tap(find.widgetWithText(AppButton, 'Login'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 110));

      expect(loginStatusFadeTransition, findsOneWidget);
      final midOpacity = tester.widget<FadeTransition>(loginStatusFadeTransition).opacity.value;
      expect(midOpacity, greaterThan(0));
      expect(midOpacity, lessThan(1));

      await tester.pumpAndSettle();
      expect(tester.widget<FadeTransition>(loginStatusFadeTransition).opacity.value, 1);
    });
  });

  group('LoginModal animations', () {
    testWidgets('forgot password panel fades in during open transition', (tester) async {
      await pumpLoginModalWidget(tester);

      await tester.tap(find.text('Forgot Password?'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 110));

      expect(loginStatusFadeTransition, findsOneWidget);
      final midOpacity = tester.widget<FadeTransition>(loginStatusFadeTransition).opacity.value;
      expect(midOpacity, greaterThan(0));
      expect(midOpacity, lessThan(1));

      await tester.pumpAndSettle();
      expect(tester.widget<FadeTransition>(loginStatusFadeTransition).opacity.value, 1);
    });

    testWidgets('forgot password panel fades out before removal', (tester) async {
      await pumpLoginModalWidget(tester, initialShowForgotPasswordInfo: true);

      await tester.tap(find.text('Forgot Password?'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 110));

      expect(loginStatusFadeTransition, findsOneWidget);
      final midOpacity = tester.widget<FadeTransition>(loginStatusFadeTransition).opacity.value;
      expect(midOpacity, greaterThan(0));
      expect(midOpacity, lessThan(1));

      await tester.pumpAndSettle();
      expect(loginStatusFadeTransition, findsNothing);
    });

    testWidgets('animated size grows modal while forgot panel opens', (tester) async {
      await pumpLoginModalWidget(tester);

      final heightBefore = tester.getSize(find.byType(LoginModal)).height;

      await tester.tap(find.text('Forgot Password?'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 110));

      final heightMid = tester.getSize(find.byType(LoginModal)).height;
      expect(heightMid, greaterThan(heightBefore));

      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(LoginModal)).height, greaterThan(heightBefore));
    });
  });

  group('LoginModal.show dialog', () {
    testWidgets('presents centered dialog with dimmed scrim', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          builder: (context, child) => ForuiAppScope(child: child ?? const SizedBox.shrink()),
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: Center(
                  child: ElevatedButton(onPressed: () => LoginModal.show(context), child: const Text('Open login')),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open login'));
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsOneWidget);
      expect(find.byType(LoginModal), findsOneWidget);
      expect(find.byType(ModalBarrier), findsWidgets);
    });

    testWidgets('close button dismisses dialog', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          builder: (context, child) => ForuiAppScope(child: child ?? const SizedBox.shrink()),
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: Center(
                  child: ElevatedButton(onPressed: () => LoginModal.show(context), child: const Text('Open login')),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open login'));
      await tester.pumpAndSettle();
      expect(find.byType(LoginModal), findsOneWidget);

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      expect(find.byType(LoginModal), findsNothing);
    });

    testWidgets('barrier tap dismisses dialog', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          builder: (context, child) => ForuiAppScope(child: child ?? const SizedBox.shrink()),
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: Center(
                  child: ElevatedButton(onPressed: () => LoginModal.show(context), child: const Text('Open login')),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open login'));
      await tester.pumpAndSettle();

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(find.byType(LoginModal), findsNothing);
    });
  });
}
