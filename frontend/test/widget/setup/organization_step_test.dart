import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/features/setup/presentation/providers/clinic_setup_notifier.dart';
import 'package:ai_clinic/features/setup/presentation/setup/steps/organization_step.dart';

import 'setup_widget_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('OrganizationStep', () {
    testWidgets('builds organization fields', (tester) async {
      await pumpSetupWidget(
        tester,
        child: const OrganizationStep(errors: {}),
        overrides: setupProviderOverrides(),
      );
      await settleSetupWidget(tester);

      expect(find.text('Your organization'), findsOneWidget);
      expect(find.text('Organization name'), findsOneWidget);
      expect(find.text('Timezone'), findsOneWidget);
      expect(find.text('Currency'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows validation errors passed from the wizard', (tester) async {
      await pumpSetupWidget(
        tester,
        child: const OrganizationStep(
          errors: {
            'name': 'Organization name is required',
            'timezone': 'Select a timezone',
            'currency': 'Select a currency',
          },
        ),
        overrides: setupProviderOverrides(),
      );
      await settleSetupWidget(tester);

      expect(find.text('Organization name is required'), findsOneWidget);
      expect(find.text('Select a timezone'), findsOneWidget);
      expect(find.text('Select a currency'), findsOneWidget);
    });

    testWidgets('updates organization name through the notifier', (tester) async {
      await pumpSetupWidget(
        tester,
        child: const OrganizationStep(errors: {}),
        overrides: setupProviderOverrides(),
      );
      await settleSetupWidget(tester);

      await enterSetupField(tester, 'org-name', 'Nile Dental');
      await settleSetupWidget(tester);

      final container = setupProviderContainer(tester);
      expect(
        container.read(clinicSetupProvider).draft.organization.name,
        'Nile Dental',
      );
    });
  });
}
