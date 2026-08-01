import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/features/setup/presentation/providers/clinic_setup_notifier.dart';
import 'package:ai_clinic/features/setup/presentation/setup/steps/services_step.dart';

import 'setup_widget_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ServicesStep', () {
    testWidgets('builds service catalog rows', (tester) async {
      await pumpSetupWidget(
        tester,
        child: const ServicesStep(errors: {}),
        overrides: setupProviderOverrides(
          setupState: defaultClinicSetupState().copyWith(
            draft: buildValidOrganizationDraft(),
          ),
        ),
      );
      await settleSetupWidget(tester);

      expect(find.text('Service catalog'), findsOneWidget);
      expect(find.text('Service name'), findsWidgets);
      expect(find.text('Price'), findsWidgets);
      expect(find.text('Add another service'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows service validation errors', (tester) async {
      await pumpSetupWidget(
        tester,
        child: const ServicesStep(
          errors: {
            'service-0-name': 'Service name is required',
            'service-0-price': 'Enter a price',
          },
        ),
        overrides: setupProviderOverrides(),
      );
      await settleSetupWidget(tester);

      expect(find.text('Service name is required'), findsOneWidget);
      expect(find.text('Enter a price'), findsOneWidget);
    });

    testWidgets('updates service name through the notifier', (tester) async {
      await pumpSetupWidget(
        tester,
        child: const ServicesStep(errors: {}),
        overrides: setupProviderOverrides(),
      );
      await settleSetupWidget(tester);

      final container = setupProviderContainer(tester);
      final serviceId = container.read(clinicSetupProvider).draft.services.first.id;

      await enterSetupField(tester, '$serviceId-name', 'Consultation');
      await settleSetupWidget(tester);

      expect(container.read(clinicSetupProvider).draft.services.first.name, 'Consultation');
    });
  });
}
