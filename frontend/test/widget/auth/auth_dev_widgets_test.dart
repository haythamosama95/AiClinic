import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/app/shell/dev/shell_dev_fill_dummy_clinic.dart';
import 'package:ai_clinic/app/shell/dev/shell_dev_reset_clinic.dart';
import 'package:ai_clinic/core/ui/components/app_button.dart';
import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/features/auth/presentation/dev/auth_dev_widgets.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const panelKey = Key('auth-dev-panel');

  Future<void> pumpPanel(
    WidgetTester tester, {
    Key? key = panelKey,
    bool isSubmitting = false,
    VoidCallback? onLoginAsAdmin,
    VoidCallback? onFillDummyClinic,
    VoidCallback? onResetClinic,
  }) async {
    var loginCount = 0;
    var fillCount = 0;
    var resetCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: AuthDevWidgets.panel(
            key: key,
            isSubmitting: isSubmitting,
            onLoginAsAdmin: onLoginAsAdmin ?? () => loginCount++,
            onFillDummyClinic: onFillDummyClinic ?? () => fillCount++,
            onResetClinic: onResetClinic ?? () => resetCount++,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }

  AppButton readAppButton(WidgetTester tester, String label) {
    return tester.widget<AppButton>(
      find.ancestor(of: find.text(label), matching: find.byType(AppButton)),
    );
  }

  group('AuthDevWidgets.panel', () {
    testWidgets('renders the three dev controls with expected labels', (tester) async {
      await pumpPanel(tester);

      expect(find.text('Dev login (admin)'), findsOneWidget);
      expect(find.text(ShellDevFillDummyClinic.label), findsOneWidget);
      expect(find.text(ShellDevResetClinic.label), findsOneWidget);
      expect(find.text('Debug builds only — uses local bootstrap credentials.'), findsOneWidget);
    });

    testWidgets('applies the key parameter to the returned widget', (tester) async {
      await pumpPanel(tester, key: panelKey);

      expect(find.byKey(panelKey), findsOneWidget);
    });

    testWidgets('login-as-admin invokes only its callback', (tester) async {
      var loginCount = 0;
      var fillCount = 0;
      var resetCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: AuthDevWidgets.panel(
              onLoginAsAdmin: () => loginCount++,
              onFillDummyClinic: () => fillCount++,
              onResetClinic: () => resetCount++,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tap(find.text('Dev login (admin)'));
      await tester.pump();

      expect(loginCount, 1);
      expect(fillCount, 0);
      expect(resetCount, 0);
    });

    testWidgets('fill-dummy-clinic invokes only its callback', (tester) async {
      var loginCount = 0;
      var fillCount = 0;
      var resetCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: AuthDevWidgets.panel(
              onLoginAsAdmin: () => loginCount++,
              onFillDummyClinic: () => fillCount++,
              onResetClinic: () => resetCount++,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tap(find.text(ShellDevFillDummyClinic.label));
      await tester.pump();

      expect(fillCount, 1);
      expect(loginCount, 0);
      expect(resetCount, 0);
    });

    testWidgets('reset-clinic invokes only its callback', (tester) async {
      var loginCount = 0;
      var fillCount = 0;
      var resetCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: AuthDevWidgets.panel(
              onLoginAsAdmin: () => loginCount++,
              onFillDummyClinic: () => fillCount++,
              onResetClinic: () => resetCount++,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tap(find.text(ShellDevResetClinic.label));
      await tester.pump();

      expect(resetCount, 1);
      expect(loginCount, 0);
      expect(fillCount, 0);
    });

    testWidgets('isSubmitting disables controls structurally via onPressed == null', (tester) async {
      await pumpPanel(tester, isSubmitting: true);

      expect(readAppButton(tester, 'Dev login (admin)').onPressed, isNull);
      expect(readAppButton(tester, ShellDevFillDummyClinic.label).onPressed, isNull);
      expect(readAppButton(tester, ShellDevResetClinic.label).onPressed, isNull);
    });

    testWidgets('tapping while isSubmitting does not invoke callbacks', (tester) async {
      var loginCount = 0;
      var fillCount = 0;
      var resetCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: AuthDevWidgets.panel(
              isSubmitting: true,
              onLoginAsAdmin: () => loginCount++,
              onFillDummyClinic: () => fillCount++,
              onResetClinic: () => resetCount++,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tap(find.text('Dev login (admin)'));
      await tester.tap(find.text(ShellDevFillDummyClinic.label));
      await tester.tap(find.text(ShellDevResetClinic.label));
      await tester.pump();

      expect(loginCount, 0);
      expect(fillCount, 0);
      expect(resetCount, 0);
    });
  });

  group('AuthDevBootstrapCredentials', () {
    test('username and password are non-empty bootstrap literals', () {
      expect(AuthDevBootstrapCredentials.username, isNotEmpty);
      expect(AuthDevBootstrapCredentials.password, isNotEmpty);
      expect(AuthDevBootstrapCredentials.username, 'admin');
      expect(AuthDevBootstrapCredentials.password, 'admin');
    });
  });

  // The `if (!kDebugMode) return SizedBox.shrink` branch in AuthDevWidgets.panel is
  // unreachable under flutter test because kDebugMode is true in test bindings.
}
