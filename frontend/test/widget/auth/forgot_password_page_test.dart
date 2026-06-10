import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/auth/presentation/widgets/login_modal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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

    expect(find.textContaining('administrator-mediated'), findsNothing);
    await tester.tap(find.text('Forgot Password?'));
    await tester.pumpAndSettle();

    expect(find.textContaining('administrator-mediated'), findsOneWidget);
    expect(find.textContaining('does not offer self-service'), findsOneWidget);
    expect(find.textContaining('Contact your clinic owner or administrator'), findsOneWidget);
    expect(find.byType(AppTextField), findsNWidgets(2));
    expect(find.text('Send reset link'), findsNothing);
  });

  testWidgets('stupid user cannot find email field or submit reset', (tester) async {
    await pumpLoginModal(tester);
    await tester.tap(find.text('Forgot Password?'));
    await tester.pumpAndSettle();

    expect(find.textContaining('email'), findsNothing);
    expect(find.widgetWithText(ElevatedButton, 'Submit'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Reset password'), findsNothing);
  });

  testWidgets('forgot password info appears below login button', (tester) async {
    await pumpLoginModal(tester);
    await tester.tap(find.text('Forgot Password?'));
    await tester.pumpAndSettle();

    final loginButton = tester.getTopLeft(find.byType(AppButton));
    final infoPanel = tester.getTopLeft(find.textContaining('administrator-mediated'));
    expect(infoPanel.dy, greaterThan(loginButton.dy));
  });

  testWidgets('page explains administrators reset passwords from settings staff', (tester) async {
    await pumpLoginModal(tester);
    await tester.tap(find.text('Forgot Password?'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Settings'), findsOneWidget);
    expect(find.textContaining('Staff'), findsOneWidget);
    expect(find.textContaining('Reset password'), findsOneWidget);
    expect(find.textContaining('owner or administrator'), findsWidgets);
  });

  testWidgets('initialShowForgotPasswordInfo opens panel without tapping link', (tester) async {
    await pumpLoginModal(tester, initialShowForgotPasswordInfo: true);

    expect(find.textContaining('administrator-mediated'), findsOneWidget);
  });

  testWidgets('corner case: panel is visible on narrow width', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: LoginModal(initialShowForgotPasswordInfo: true))));
    await tester.pumpAndSettle();

    expect(find.textContaining('administrator-mediated'), findsOneWidget);
  });
}
