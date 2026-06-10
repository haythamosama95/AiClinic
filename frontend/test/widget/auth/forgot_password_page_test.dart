import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/auth/presentation/providers/auth_notifier.dart';
import 'package:ai_clinic/features/auth/presentation/widgets/login_modal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Finder visiblePanelText(Key panelKey, String text) {
  return find.descendant(
    of: find.descendant(of: find.byKey(panelKey), matching: find.byType(FadeTransition)),
    matching: find.textContaining(text),
  );
}

void main() {
  Future<void> pumpLoginModal(WidgetTester tester, {bool initialShowForgotPasswordInfo = false}) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: LoginModal(initialShowForgotPasswordInfo: initialShowForgotPasswordInfo)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows administrator-mediated recovery message only after forgot password tap', (tester) async {
    await pumpLoginModal(tester);

    const statusPanelKey = ValueKey('login-status-panel');
    final visibleInfoText = visiblePanelText(statusPanelKey, 'administrator-mediated');
    final forgotPanelFade = find.descendant(of: find.byKey(statusPanelKey), matching: find.byType(FadeTransition));

    expect(visibleInfoText, findsNothing);
    expect(forgotPanelFade, findsNothing);

    await tester.tap(find.text('Forgot Password?'));
    await tester.pumpAndSettle();

    expect(visibleInfoText, findsOneWidget);
    expect(forgotPanelFade, findsOneWidget);
    expect(tester.widget<FadeTransition>(forgotPanelFade).opacity.value, 1);
    expect(visiblePanelText(statusPanelKey, 'does not offer self-service'), findsOneWidget);
    expect(visiblePanelText(statusPanelKey, 'Contact your clinic owner or administrator'), findsOneWidget);
    expect(find.byType(AppTextField), findsNWidgets(2));
    expect(find.text('Send reset link'), findsNothing);
  });

  testWidgets('does not show sign-in error alert before failed login', (tester) async {
    await pumpLoginModal(tester);

    expect(visiblePanelText(const ValueKey('login-status-panel'), 'incorrect'), findsNothing);
  });

  testWidgets('stupid user cannot find email field or submit reset', (tester) async {
    await pumpLoginModal(tester);
    await tester.tap(find.text('Forgot Password?'));
    await tester.pumpAndSettle();

    expect(find.textContaining('email'), findsNothing);
    expect(find.widgetWithText(ElevatedButton, 'Submit'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Reset password'), findsNothing);
  });

  testWidgets('toggling forgot password does not resize the modal', (tester) async {
    await pumpLoginModal(tester);

    final modalHeightBefore = tester.getSize(find.byType(LoginModal)).height;

    await tester.tap(find.text('Forgot Password?'));
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byType(LoginModal)).height, modalHeightBefore);

    await tester.tap(find.text('Forgot Password?'));
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byType(LoginModal)).height, modalHeightBefore);
  });

  testWidgets('forgot password info appears below login button', (tester) async {
    await pumpLoginModal(tester);
    await tester.tap(find.text('Forgot Password?'));
    await tester.pumpAndSettle();

    final loginButton = tester.getTopLeft(find.byType(AppButton));
    final infoPanel = tester.getTopLeft(
      visiblePanelText(const ValueKey('login-status-panel'), 'administrator-mediated'),
    );
    expect(infoPanel.dy, greaterThan(loginButton.dy));
  });

  testWidgets('page explains administrators reset passwords from settings staff', (tester) async {
    await pumpLoginModal(tester);
    await tester.tap(find.text('Forgot Password?'));
    await tester.pumpAndSettle();

    const statusPanelKey = ValueKey('login-status-panel');
    expect(visiblePanelText(statusPanelKey, 'Settings'), findsOneWidget);
    expect(visiblePanelText(statusPanelKey, 'Staff'), findsOneWidget);
    expect(visiblePanelText(statusPanelKey, 'Reset password'), findsOneWidget);
    expect(visiblePanelText(statusPanelKey, 'owner or administrator'), findsOneWidget);
  });

  testWidgets('initialShowForgotPasswordInfo opens panel without tapping link', (tester) async {
    await pumpLoginModal(tester, initialShowForgotPasswordInfo: true);

    expect(visiblePanelText(const ValueKey('login-status-panel'), 'administrator-mediated'), findsOneWidget);
  });

  testWidgets('opening forgot password dismisses sign-in error permanently', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    String? errorMessage = kGenericSignInFailureMessage;
    var dismissCount = 0;

    Future<void> pumpModal() async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return LoginModal(
                  errorMessage: errorMessage,
                  onDismissSignInError: () {
                    dismissCount++;
                    setState(() => errorMessage = null);
                  },
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await pumpModal();

    const statusPanelKey = ValueKey('login-status-panel');
    expect(visiblePanelText(statusPanelKey, 'incorrect'), findsOneWidget);

    await tester.tap(find.text('Forgot Password?'));
    await tester.pumpAndSettle();

    expect(dismissCount, 1);
    expect(visiblePanelText(statusPanelKey, 'administrator-mediated'), findsOneWidget);
    expect(visiblePanelText(statusPanelKey, 'incorrect'), findsNothing);

    await tester.tap(find.text('Forgot Password?'));
    await tester.pumpAndSettle();

    expect(visiblePanelText(statusPanelKey, 'incorrect'), findsNothing);
    expect(visiblePanelText(statusPanelKey, 'administrator-mediated'), findsNothing);
  });

  testWidgets('close button resets modal and clears parent sign-in error', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    String? errorMessage = kGenericSignInFailureMessage;
    var closed = false;
    var presentationGeneration = 0;

    Future<void> pumpModal() async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return LoginModal(
                  key: ValueKey(presentationGeneration),
                  errorMessage: errorMessage,
                  onDismissSignInError: () => setState(() => errorMessage = null),
                  onClose: () {
                    closed = true;
                    setState(() {
                      errorMessage = null;
                      presentationGeneration++;
                    });
                  },
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await pumpModal();

    const statusPanelKey = ValueKey('login-status-panel');

    await tester.enterText(find.byType(AppTextField).at(0), 'staff1');
    await tester.enterText(find.byType(AppTextField).at(1), 'secret');
    await tester.tap(find.text('Forgot Password?'));
    await tester.pumpAndSettle();

    expect(visiblePanelText(statusPanelKey, 'administrator-mediated'), findsOneWidget);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    expect(closed, isTrue);
    expect(errorMessage, isNull);
    expect(find.text('staff1'), findsNothing);
    expect(visiblePanelText(statusPanelKey, 'administrator-mediated'), findsNothing);
    expect(visiblePanelText(statusPanelKey, 'incorrect'), findsNothing);
  });

  testWidgets('corner case: panel is visible on narrow width', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: LoginModal(initialShowForgotPasswordInfo: true))));
    await tester.pumpAndSettle();

    expect(visiblePanelText(const ValueKey('login-status-panel'), 'administrator-mediated'), findsOneWidget);
  });
}
