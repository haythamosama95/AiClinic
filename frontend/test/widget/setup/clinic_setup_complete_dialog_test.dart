import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/features/setup/presentation/widgets/clinic_setup_complete_dialog.dart';

import 'setup_widget_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpDialogHost(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => ClinicSetupCompleteDialog.show(
              context,
              draft: buildValidSetupDraft(),
            ),
            child: const Text('Open complete'),
          ),
        ),
      ),
    );
  }

  Future<void> openDialog(WidgetTester tester) async {
    await pumpDialogHost(tester);
    await tester.tap(find.text('Open complete'));
    await tester.pump(const Duration(milliseconds: 200));
  }

  group('ClinicSetupCompleteDialog.show', () {
    testWidgets('presents celebration copy from the setup draft', (tester) async {
      await openDialog(tester);

      expect(find.text('Your clinic is ready'), findsOneWidget);
      expect(find.text('Nile Dental is good to go'), findsOneWidget);
      expect(
        find.textContaining('1 branch'),
        findsOneWidget,
      );
      expect(find.text('Start exploring'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('dismisses when Start exploring is tapped', (tester) async {
      await openDialog(tester);

      await tester.tap(find.text('Start exploring'));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Your clinic is ready'), findsNothing);
    });

    testWidgets('is non-dismissible via barrier tap', (tester) async {
      await openDialog(tester);

      await tester.tapAt(const Offset(8, 8));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Your clinic is ready'), findsOneWidget);
    });
  });
}
