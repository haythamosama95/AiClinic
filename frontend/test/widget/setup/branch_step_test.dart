import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/features/setup/presentation/providers/clinic_setup_notifier.dart';
import 'package:ai_clinic/features/setup/presentation/setup/steps/branch_step.dart';

import 'setup_widget_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BranchStep', () {
    testWidgets('builds branch form for the active branch', (tester) async {
      await pumpSetupWidget(
        tester,
        child: const BranchStep(errors: {}),
        overrides: setupProviderOverrides(),
      );
      await settleSetupWidget(tester);

      expect(find.text('Branches'), findsOneWidget);
      expect(find.text('Branch 1'), findsOneWidget);
      expect(find.text('Branch name'), findsOneWidget);
      expect(find.text('Branch code'), findsOneWidget);
      expect(find.text('Add another branch'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows branch validation errors', (tester) async {
      await pumpSetupWidget(
        tester,
        child: const BranchStep(
          errors: {
            'branch-0-name': 'Branch name is required',
            'branch-0-code': 'Branch code is required',
          },
        ),
        overrides: setupProviderOverrides(),
      );
      await settleSetupWidget(tester);

      expect(find.text('Branch name is required'), findsOneWidget);
      expect(find.text('Branch code is required'), findsOneWidget);
    });

    testWidgets('updates branch name through the notifier', (tester) async {
      await pumpSetupWidget(
        tester,
        child: const BranchStep(errors: {}),
        overrides: setupProviderOverrides(),
      );
      await settleSetupWidget(tester);

      final container = setupProviderContainer(tester);
      final branchId = container.read(clinicSetupProvider).draft.branches.first.id;

      await enterSetupField(tester, '$branchId-name', 'Zamalek');
      await settleSetupWidget(tester);

      expect(container.read(clinicSetupProvider).draft.branches.first.name, 'Zamalek');
    });
  });
}
