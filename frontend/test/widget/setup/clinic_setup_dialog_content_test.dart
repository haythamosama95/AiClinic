import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/setup/presentation/setup/setup_wizard.dart';

import '../../helpers/auth_test_support.dart';
import 'setup_widget_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ClinicSetupDialogContent hydration', () {
    testWidgets('shows loading state while hydration is in progress', (tester) async {
      await pumpClinicSetupDialogContent(
        tester,
        overrides: setupProviderOverrides(hydrationOverride: setupHydrationLoadingOverride()),
      );
      await pumpSetupFrames(tester);

      expect(find.text('Setup'), findsOneWidget);
      expect(find.textContaining('Walk through the essentials'), findsOneWidget);
      expect(find.byType(SetupWizard), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows error state with retry action when hydration fails', (tester) async {
      await pumpClinicSetupDialogContent(
        tester,
        overrides: setupProviderOverrides(hydrationOverride: setupHydrationErrorOverride()),
      );
      await pumpUntilSetupFinder(tester, find.text('Unable to load clinic setup'));
      expect(find.text('Check your connection and try again.'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.byType(SetupWizard), findsNothing);
    });

    testWidgets('retry invalidates hydration and shows wizard after success', (tester) async {
      await pumpClinicSetupDialogContent(
        tester,
        overrides: setupProviderOverrides(hydrationOverride: setupHydrationErrorOverride()),
      );
      await pumpUntilSetupFinder(tester, find.text('Unable to load clinic setup'));
      expect(find.text('Retry'), findsOneWidget);

      await tester.ensureVisible(find.text('Retry'));
      await tester.tap(find.text('Retry'));
      await tester.pump();

      await pumpClinicSetupDialogContent(tester);
      await settleSetupWidget(tester);

      expect(find.byType(SetupWizard), findsOneWidget);
    });
  });

  group('ClinicSetupDialogContent setup body', () {
    testWidgets('shows wizard when setup is incomplete and user can run bootstrap', (tester) async {
      await pumpClinicSetupDialogContent(tester);
      await settleSetupWidget(tester);

      expect(find.byType(SetupWizard), findsOneWidget);
      expect(find.text('Your organization'), findsOneWidget);
    });

    testWidgets('shows administrator warning when bootstrap setup is not allowed', (tester) async {
      await pumpClinicSetupDialogContent(
        tester,
        auth: AuthSessionState(
          status: AuthSessionStatus.authenticated,
          context: sampleAuthSessionContext(setupRequired: true, isBootstrapAdmin: false, role: StaffRole.receptionist),
        ),
      );
      await settleSetupWidget(tester);

      expect(find.text('Administrator sign-in required'), findsOneWidget);
      expect(find.byType(SetupWizard), findsNothing);
    });

    testWidgets('shows completed banner when setup is already done', (tester) async {
      await pumpClinicSetupDialogContent(
        tester,
        auth: setupAuthSession(setupRequired: false),
        setupState: presetClinicSetupState().copyWith(completed: true),
      );
      await settleSetupWidget(tester);

      expect(find.text('Setup complete'), findsOneWidget);
      expect(find.text('Run setup again'), findsOneWidget);
      expect(find.byType(SetupWizard), findsNothing);
    });
  });
}
