import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/features/setup/presentation/setup/setup_draft_models.dart';
import 'package:ai_clinic/features/setup/presentation/setup/widgets/collapsed_staff_card.dart';

import 'setup_widget_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CollapsedStaffCard', () {
    testWidgets('shows staff summary and subtitle details', (tester) async {
      final member = createEmptyStaff().copyWith(
        name: 'Dr. Sara Hassan',
        role: 'doctor',
        username: 'sarah',
        mobile: '1000000001',
        branchIds: const ['branch-a', 'branch-b'],
      );

      await pumpSetupWidget(
        tester,
        child: CollapsedStaffCard(
          member: member,
          index: 0,
          onExpand: () {},
          onRemove: () {},
        ),
        scrollable: false,
      );
      await settleSetupWidget(tester);

      expect(find.text('Dr. Sara Hassan'), findsOneWidget);
      expect(find.textContaining('Doctor'), findsOneWidget);
      expect(find.textContaining('sarah'), findsOneWidget);
      expect(find.textContaining('1000000001'), findsOneWidget);
      expect(find.textContaining('2 branches'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('falls back to numbered title when staff name is empty', (tester) async {
      await pumpSetupWidget(
        tester,
        child: CollapsedStaffCard(
          member: createEmptyStaff(),
          index: 2,
          onExpand: () {},
          onRemove: () {},
        ),
        scrollable: false,
      );
      await settleSetupWidget(tester);

      expect(find.text('Staff member 3'), findsOneWidget);
    });

    testWidgets('invokes expand and remove callbacks', (tester) async {
      var expanded = false;
      var removed = false;
      final member = createEmptyStaff().copyWith(name: 'Reception Lead');

      await pumpSetupWidget(
        tester,
        child: CollapsedStaffCard(
          member: member,
          index: 0,
          onExpand: () => expanded = true,
          onRemove: () => removed = true,
        ),
        scrollable: false,
      );
      await settleSetupWidget(tester);

      await tester.tap(find.text('Reception Lead'));
      await settleSetupWidget(tester);
      expect(expanded, isTrue);

      await tester.tap(find.bySemanticsLabel('Remove staff member'));
      await settleSetupWidget(tester);
      expect(removed, isTrue);
    });
  });
}
