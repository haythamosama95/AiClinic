import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/features/setup/presentation/providers/clinic_setup_notifier.dart';
import 'package:ai_clinic/features/setup/presentation/setup/steps/staff_step.dart';

import 'setup_widget_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('StaffStep', () {
    testWidgets('builds staff form for the active member', (tester) async {
      await pumpSetupWidget(
        tester,
        child: const StaffStep(errors: {}),
        overrides: setupProviderOverrides(
          setupState: defaultClinicSetupState().copyWith(
            draft: buildValidOrganizationDraft(),
          ),
        ),
      );
      await settleSetupWidget(tester);

      expect(find.text('Staff'), findsOneWidget);
      expect(find.text('Staff member 1'), findsOneWidget);
      expect(find.text('Full name'), findsOneWidget);
      expect(find.text('Mobile'), findsOneWidget);
      expect(find.text('Add another staff member'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows staff validation errors', (tester) async {
      await pumpSetupWidget(
        tester,
        child: const StaffStep(
          errors: {
            'staff-0-name': 'Name is required',
            'staff-0-username': 'Username is required',
          },
        ),
        overrides: setupProviderOverrides(),
      );
      await settleSetupWidget(tester);

      expect(find.text('Name is required'), findsOneWidget);
      expect(find.text('Username is required'), findsOneWidget);
    });

    testWidgets('updates staff name through the notifier', (tester) async {
      await pumpSetupWidget(
        tester,
        child: const StaffStep(errors: {}),
        overrides: setupProviderOverrides(),
      );
      await settleSetupWidget(tester);

      final container = setupProviderContainer(tester);
      final staffId = container.read(clinicSetupProvider).draft.staff.first.id;

      await enterSetupField(tester, '$staffId-name', 'Dr. Sara Hassan');
      await settleSetupWidget(tester);

      expect(container.read(clinicSetupProvider).draft.staff.first.name, 'Dr. Sara Hassan');
    });
  });
}
