import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/auth/presentation/providers/auth_notifier.dart';
import 'package:ai_clinic/features/auth/presentation/widgets/login_modal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'login_modal_test_support.dart';

void main() {
  group('LoginModal forgot password', () {
    testWidgets('shows administrator-mediated recovery message only after forgot password tap', (tester) async {
      await pumpLoginModalWidget(tester);

      expect(visiblePanelText('administrator-mediated'), findsNothing);
      expect(loginStatusFadeTransition, findsNothing);

      await tester.tap(find.text('Forgot Password?'));
      await tester.pumpAndSettle();

      expect(visiblePanelText('administrator-mediated'), findsOneWidget);
      expect(loginStatusFadeTransition, findsOneWidget);
      expect(tester.widget<FadeTransition>(loginStatusFadeTransition).opacity.value, 1);
      expect(visiblePanelText('does not offer self-service'), findsOneWidget);
      expect(visiblePanelText('Contact your clinic administrator'), findsOneWidget);
      expect(find.byType(AppTextField), findsNWidgets(2));
      expect(find.text('Send reset link'), findsNothing);
    });

    testWidgets('does not show sign-in error alert before failed login', (tester) async {
      await pumpLoginModalWidget(tester);

      expect(visiblePanelText('incorrect'), findsNothing);
    });

    testWidgets('stupid user cannot find email field or submit reset', (tester) async {
      await pumpLoginModalWidget(tester);
      await tester.tap(find.text('Forgot Password?'));
      await tester.pumpAndSettle();

      expect(find.textContaining('email'), findsNothing);
      expect(find.widgetWithText(ElevatedButton, 'Submit'), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Reset password'), findsNothing);
    });

    testWidgets('showing forgot password panel grows modal and shifts form upward', (tester) async {
      await pumpLoginModalWidget(tester);

      final modalHeightBefore = tester.getSize(find.byType(LoginModal)).height;
      final loginButtonYBefore = tester.getCenter(find.byType(AppButton)).dy;

      await tester.tap(find.text('Forgot Password?'));
      await tester.pumpAndSettle();

      expect(tester.getSize(find.byType(LoginModal)).height, greaterThan(modalHeightBefore));
      expect(tester.getCenter(find.byType(AppButton)).dy, lessThan(loginButtonYBefore));

      await tester.tap(find.text('Forgot Password?'));
      await tester.pumpAndSettle();

      expect(tester.getSize(find.byType(LoginModal)).height, modalHeightBefore);
      expect(tester.getCenter(find.byType(AppButton)).dy, loginButtonYBefore);
    });

    testWidgets('forgot password info appears below login button', (tester) async {
      await pumpLoginModalWidget(tester);
      await tester.tap(find.text('Forgot Password?'));
      await tester.pumpAndSettle();

      final loginButton = tester.getTopLeft(find.byType(AppButton));
      final infoPanel = tester.getTopLeft(visiblePanelText('administrator-mediated'));
      expect(infoPanel.dy, greaterThan(loginButton.dy));
    });

    testWidgets('page explains administrators reset passwords from settings staff', (tester) async {
      await pumpLoginModalWidget(tester);
      await tester.tap(find.text('Forgot Password?'));
      await tester.pumpAndSettle();

      expect(visiblePanelText('Settings'), findsOneWidget);
      expect(visiblePanelText('Staff'), findsOneWidget);
      expect(visiblePanelText('Reset password'), findsOneWidget);
      expect(visiblePanelText('administrator account'), findsOneWidget);
    });

    testWidgets('initialShowForgotPasswordInfo opens panel without tapping link', (tester) async {
      await pumpLoginModalWidget(tester, initialShowForgotPasswordInfo: true);

      expect(visiblePanelText('administrator-mediated'), findsOneWidget);
    });

    testWidgets('opening forgot password dismisses sign-in error permanently', (tester) async {
      String? errorMessage = kGenericSignInFailureMessage;
      var dismissCount = 0;

      Future<void> pumpModal() async {
        await pumpLoginModal(
          tester,
          child: StatefulBuilder(
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
        );
      }

      await pumpModal();

      expect(visiblePanelText('incorrect'), findsOneWidget);

      await tester.tap(find.text('Forgot Password?'));
      await tester.pumpAndSettle();

      expect(dismissCount, 1);
      expect(visiblePanelText('administrator-mediated'), findsOneWidget);
      expect(visiblePanelText('incorrect'), findsNothing);

      await tester.tap(find.text('Forgot Password?'));
      await tester.pumpAndSettle();

      expect(visiblePanelText('incorrect'), findsNothing);
      expect(visiblePanelText('administrator-mediated'), findsNothing);
    });

    testWidgets('close button resets modal and clears parent sign-in error', (tester) async {
      String? errorMessage = kGenericSignInFailureMessage;
      var closed = false;
      var presentationGeneration = 0;

      Future<void> pumpModal() async {
        await pumpLoginModal(
          tester,
          child: StatefulBuilder(
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
        );
      }

      await pumpModal();

      await tester.enterText(find.byType(AppTextField).at(0), 'staff1');
      await tester.enterText(find.byType(AppTextField).at(1), 'secret');
      await tester.tap(find.text('Forgot Password?'));
      await tester.pumpAndSettle();

      expect(visiblePanelText('administrator-mediated'), findsOneWidget);

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      expect(closed, isTrue);
      expect(errorMessage, isNull);
      expect(find.text('staff1'), findsNothing);
      expect(visiblePanelText('administrator-mediated'), findsNothing);
      expect(visiblePanelText('incorrect'), findsNothing);
    });

    testWidgets('corner case: panel is visible on narrow width', (tester) async {
      await pumpLoginModalWidget(tester, initialShowForgotPasswordInfo: true, size: const Size(320, 1200));

      expect(visiblePanelText('administrator-mediated'), findsOneWidget);
    });
  });
}
