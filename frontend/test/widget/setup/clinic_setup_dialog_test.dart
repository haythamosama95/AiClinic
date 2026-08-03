import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/features/setup/presentation/setup/setup_wizard.dart';
import 'package:ai_clinic/features/setup/presentation/widgets/clinic_setup_dialog.dart';

import 'setup_widget_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const dialogSurfaceSize = Size(1400, 1000);

  Future<void> pumpDialogHost(
    WidgetTester tester, {
    List<Override> overrides = const [],
  }) async {
    await tester.binding.setSurfaceSize(dialogSurfaceSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides.isNotEmpty ? overrides : setupProviderOverrides(),
        child: MaterialApp(
          theme: AppTheme.light(),
          builder: (context, child) => MediaQuery(
            data: const MediaQueryData(size: dialogSurfaceSize),
            child: child!,
          ),
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => ClinicSetupDialog.show(context),
              child: const Text('Open setup'),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> openDialog(WidgetTester tester, {List<Override> overrides = const []}) async {
    await pumpDialogHost(tester, overrides: overrides);
    await tester.tap(find.text('Open setup'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));
  }

  group('ClinicSetupDialog.show', () {
    testWidgets('presents embedded setup wizard for bootstrap setup', (tester) async {
      await openDialog(tester);

      expect(find.byType(SetupWizard), findsOneWidget);
      expect(find.text('Clinic setup'), findsOneWidget);
      expect(find.text('Your organization'), findsOneWidget);
    });

    testWidgets('is non-dismissible via barrier tap while setup is required', (tester) async {
      await openDialog(tester);

      await tester.tapAt(const Offset(8, 8));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(SetupWizard), findsOneWidget);
    });

    testWidgets('is non-dismissible via back navigation while setup is required', (tester) async {
      await openDialog(tester);

      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(SetupWizard), findsOneWidget);
    });
  });
}
