import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/features/setup/presentation/providers/clinic_setup_notifier.dart';
import 'package:ai_clinic/features/setup/presentation/setup/setup_wizard.dart';

import 'setup_widget_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SetupWizard', () {
    testWidgets('builds with clinic setup header and step content', (tester) async {
      await pumpSetupWizard(tester);
      await settleSetupWidget(tester);

      expect(find.byType(SetupWizard), findsOneWidget);
      expect(find.text('Clinic setup'), findsOneWidget);
      expect(find.text('Your organization'), findsOneWidget);
      expect(find.text('Step 1 of 4'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows step rail labels at wide width', (tester) async {
      await pumpSetupWizard(tester, surfaceSize: setupWideSurfaceSize);
      await settleSetupWidget(tester);

      expect(find.text('Organization'), findsOneWidget);
      expect(find.text('Branch'), findsOneWidget);
      expect(find.text('Staff'), findsOneWidget);
      expect(find.text('Services'), findsOneWidget);
      expect(find.text('Name & region'), findsOneWidget);
      expect(find.text('Locations & hours'), findsOneWidget);
    });

    testWidgets('continue advances to the next step', (tester) async {
      ignoreKnownSetupTestExceptions();
      await pumpSetupWizard(
        tester,
        setupState: defaultClinicSetupState().copyWith(draft: buildValidOrganizationDraft()),
      );
      await tester.pump();

      final container = setupProviderContainer(tester);
      expect(container.read(clinicSetupProvider).step, 0);

      await tapSetupContinue(tester);
      await tester.pump();

      expect(container.read(clinicSetupProvider).step, 1);
    });

    testWidgets('back button is enabled after the first step', (tester) async {
      ignoreKnownSetupTestExceptions();
      await pumpSetupWizard(
        tester,
        setupState: defaultClinicSetupState(step: 1).copyWith(draft: buildValidOrganizationDraft()),
      );
      await tester.pump();

      final backButton = setupButtonAncestor(setupBackButton());
      expect(isSetupButtonDisabled(backButton), isFalse);
    });

    testWidgets('back button is disabled on the first step', (tester) async {
      await pumpSetupWizard(tester);
      await settleSetupWidget(tester);

      final backButton = setupButtonAncestor(setupBackButton());
      expect(isSetupButtonDisabled(backButton), isTrue);
    });

    testWidgets('validation blocks advancing from organization step', (tester) async {
      ignoreKnownSetupTestExceptions();
      await pumpSetupWizard(tester);
      await pumpSetupFrames(tester);

      final container = setupProviderContainer(tester);

      await tapSetupContinue(tester);
      await tester.pump(const Duration(milliseconds: 200));

      expect(container.read(clinicSetupProvider).step, 0);
      expect(find.text('Your organization'), findsOneWidget);
      expect(find.text('Organization name is required'), findsOneWidget);
      expect(find.text('Branches'), findsNothing);
    });

    testWidgets('shows submit error when completeSetup fails', (tester) async {
      ignoreKnownSetupTestExceptions();
      late SpyClinicSetupNotifier notifier;

      await pumpSetupWizard(
        tester,
        overrides: setupProviderOverrides(
          clinicSetupOverride: clinicSetupProvider.overrideWith((ref) {
            notifier = SpyClinicSetupNotifier(ref, presetClinicSetupState(step: 3));
            notifier.completeSetupError = 'Setup failed on the server';
            notifier.completeSetupResult = false;
            return notifier;
          }),
        ),
      );
      await pumpSetupFrames(tester);

      await tester.tap(find.text('Finish setup'));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(notifier.completeSetupCallCount, 1);
      expect(find.text('Setup failed on the server'), findsOneWidget);
      drainSetupTestExceptions(tester);
    });

    testWidgets('shows submit error from clinic setup state', (tester) async {
      await pumpSetupWizard(
        tester,
        setupState: presetClinicSetupState(step: 3, submitError: 'Unable to save clinic setup.'),
      );
      await settleSetupWidget(tester);

      expect(find.text('Unable to save clinic setup.'), findsOneWidget);
      expect(find.text('Finish setup'), findsOneWidget);
    });

    testWidgets('shows submitting state on the final step', (tester) async {
      await pumpSetupWizard(tester, setupState: presetClinicSetupState(step: 3, isSubmitting: true));
      await settleSetupWidget(tester);

      expect(find.text('Finishing setup…'), findsOneWidget);

      final continueButton = setupButtonAncestor(find.text('Finishing setup…'));
      expect(isSetupButtonDisabled(continueButton), isTrue);

      final backButton = setupButtonAncestor(setupBackButton());
      expect(isSetupButtonDisabled(backButton), isTrue);
    });
  });
}
