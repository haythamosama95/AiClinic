import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/core/ui/components/app_button.dart';
import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/features/auth/presentation/widgets/clinic_setup_welcome_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const welcomeBody =
      'You are signed in as the clinic administrator. Before your team can use the workspace, '
      'we will walk you through a short setup for your organization, branches, staff, and services.';

  const welcomeInfoBox =
      'Next up: a short setup wizard will open here. It only takes a few minutes, and you can adjust everything later in Settings.';

  Future<void> pumpDialogHost(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => ClinicSetupWelcomeDialog.show(context),
            child: const Text('Open welcome'),
          ),
        ),
      ),
    );
  }

  Future<void> openDialog(WidgetTester tester) async {
    await pumpDialogHost(tester);
    await tester.tap(find.text('Open welcome'));
    await tester.pump(const Duration(milliseconds: 200));
  }

  group('ClinicSetupWelcomeDialog.show', () {
    testWidgets('presents dialog with app name and expected copy', (tester) async {
      await openDialog(tester);

      expect(find.text('Welcome to ${ClinicSetupWelcomeDialog.appName}'), findsOneWidget);
      expect(find.text(welcomeBody), findsOneWidget);
      expect(find.text(welcomeInfoBox), findsOneWidget);
      expect(find.byIcon(Icons.auto_fix_high), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);
    });

    testWidgets('does not require a ProviderScope', (tester) async {
      await openDialog(tester);

      expect(find.text('Welcome to ${ClinicSetupWelcomeDialog.appName}'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('is non-dismissible via barrier tap', (tester) async {
      await openDialog(tester);

      await tester.tapAt(const Offset(8, 8));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Welcome to ${ClinicSetupWelcomeDialog.appName}'), findsOneWidget);
    });

    testWidgets('is non-dismissible via back navigation', (tester) async {
      await openDialog(tester);

      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Welcome to ${ClinicSetupWelcomeDialog.appName}'), findsOneWidget);
    });

    testWidgets('returns a Future that completes only after Continue is tapped', (tester) async {
      var completed = false;

      await tester.binding.setSurfaceSize(const Size(800, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                ClinicSetupWelcomeDialog.show(context).then((_) => completed = true);
              },
              child: const Text('Open welcome'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open welcome'));
      await tester.pump(const Duration(milliseconds: 200));

      expect(completed, isFalse);
      expect(find.text('Welcome to ${ClinicSetupWelcomeDialog.appName}'), findsOneWidget);

      await tester.tap(find.text('Continue'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(completed, isTrue);
      expect(find.text('Welcome to ${ClinicSetupWelcomeDialog.appName}'), findsNothing);
    });

    testWidgets('Continue dismisses the dialog', (tester) async {
      await openDialog(tester);

      await tester.tap(find.text('Continue'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Welcome to ${ClinicSetupWelcomeDialog.appName}'), findsNothing);
    });

    testWidgets('Continue button is an enabled AppButton before dismissal', (tester) async {
      await openDialog(tester);

      final continueButton = tester.widget<AppButton>(
        find.ancestor(of: find.text('Continue'), matching: find.byType(AppButton)),
      );
      expect(continueButton.onPressed, isNotNull);
    });
  });
}
