import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/features/setup/presentation/setup/setup_step_rail.dart';

import 'setup_widget_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SetupStepRail', () {
    testWidgets('renders all setup step labels and descriptions', (tester) async {
      await pumpSetupWidget(
        tester,
        child: const SetupStepRail(currentStep: 0),
      );
      await settleSetupWidget(tester);

      expect(find.text('Organization'), findsOneWidget);
      expect(find.text('Branch'), findsOneWidget);
      expect(find.text('Staff'), findsOneWidget);
      expect(find.text('Services'), findsOneWidget);
      expect(find.text('Name & region'), findsOneWidget);
      expect(find.text('Locations & hours'), findsOneWidget);
      expect(find.text('Team & access'), findsOneWidget);
      expect(find.text('Catalog & pricing'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('builds for each wizard step index', (tester) async {
      for (var step = 0; step < 4; step++) {
        await pumpSetupWidget(
          tester,
          child: SetupStepRail(currentStep: step),
        );
        await settleSetupWidget(tester);

        expect(find.byType(SetupStepRail), findsOneWidget);
        expect(find.text('Organization'), findsOneWidget);
      }
    });
  });
}
