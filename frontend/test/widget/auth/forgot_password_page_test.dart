import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/features/auth/presentation/pages/forgot_password_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  Future<void> pumpForgotPage(WidgetTester tester, {GoRouter? router}) async {
    if (router != null) {
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    } else {
      await tester.pumpWidget(const MaterialApp(home: ForgotPasswordPage()));
    }
    await tester.pumpAndSettle();
  }

  testWidgets('shows administrator-mediated recovery message only', (tester) async {
    await pumpForgotPage(tester);

    expect(find.textContaining('administrator-mediated'), findsOneWidget);
    expect(find.textContaining('does not offer self-service'), findsOneWidget);
    expect(find.textContaining('Contact your clinic owner or administrator'), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
    expect(find.text('Reset password'), findsNothing);
    expect(find.text('Send reset link'), findsNothing);
  });

  testWidgets('stupid user cannot find email field or submit reset', (tester) async {
    await pumpForgotPage(tester);

    expect(find.byType(TextField), findsNothing);
    expect(find.byType(TextFormField), findsNothing);
    expect(find.widgetWithText(ElevatedButton, 'Submit'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Reset password'), findsNothing);
  });

  testWidgets('back to sign in navigates to login route', (tester) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: AppRoutes.login,
          builder: (context, state) => const Scaffold(body: Text('Login screen')),
        ),
        GoRoute(path: AppRoutes.forgotPassword, builder: (context, state) => const ForgotPasswordPage()),
      ],
      initialLocation: AppRoutes.forgotPassword,
    );

    await pumpForgotPage(tester, router: router);
    await tester.tap(find.text('Back to sign in'));
    await tester.pumpAndSettle();

    expect(find.text('Login screen'), findsOneWidget);
  });

  testWidgets('page explains administrators reset passwords from settings staff', (tester) async {
    await pumpForgotPage(tester);

    expect(find.textContaining('Settings'), findsOneWidget);
    expect(find.textContaining('Staff'), findsOneWidget);
    expect(find.textContaining('Reset password'), findsOneWidget);
    expect(find.textContaining('owner or administrator'), findsWidgets);
  });

  testWidgets('corner case: page renders without overflow on narrow width', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pumpForgotPage(tester);

    expect(tester.takeException(), isNull);
    expect(find.byType(ForgotPasswordPage), findsOneWidget);
  });
}
