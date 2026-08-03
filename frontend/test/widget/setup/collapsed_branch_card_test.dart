import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/features/setup/presentation/setup/setup_draft_models.dart';
import 'package:ai_clinic/features/setup/presentation/setup/widgets/collapsed_branch_card.dart';

import 'setup_widget_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CollapsedBranchCard', () {
    testWidgets('shows branch summary and subtitle details', (tester) async {
      final branch = createEmptyBranch().copyWith(
        name: 'Zamalek',
        code: 'ZMK',
        mobile: '1000000000',
      );

      await pumpSetupWidget(
        tester,
        child: CollapsedBranchCard(
          branch: branch,
          index: 0,
          onExpand: () {},
          onRemove: () {},
        ),
        scrollable: false,
      );
      await settleSetupWidget(tester);

      expect(find.text('Zamalek'), findsOneWidget);
      expect(find.textContaining('ZMK'), findsOneWidget);
      expect(find.textContaining('1000000000'), findsOneWidget);
      expect(find.textContaining('open days'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('falls back to numbered title when branch name is empty', (tester) async {
      await pumpSetupWidget(
        tester,
        child: CollapsedBranchCard(
          branch: createEmptyBranch(),
          index: 1,
          onExpand: () {},
          onRemove: () {},
        ),
        scrollable: false,
      );
      await settleSetupWidget(tester);

      expect(find.text('Branch 2'), findsOneWidget);
    });

    testWidgets('invokes expand and remove callbacks', (tester) async {
      var expanded = false;
      var removed = false;
      final branch = createEmptyBranch().copyWith(name: 'Downtown');

      await pumpSetupWidget(
        tester,
        child: CollapsedBranchCard(
          branch: branch,
          index: 0,
          onExpand: () => expanded = true,
          onRemove: () => removed = true,
        ),
        scrollable: false,
      );
      await settleSetupWidget(tester);

      await tester.tap(find.text('Downtown'));
      await settleSetupWidget(tester);
      expect(expanded, isTrue);

      await tester.tap(find.bySemanticsLabel('Remove branch'));
      await settleSetupWidget(tester);
      expect(removed, isTrue);
    });
  });
}
