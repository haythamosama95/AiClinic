import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/core/ui/components/app_checkbox.dart';
import 'package:ai_clinic/features/setup/presentation/setup/setup_draft_models.dart';
import 'package:ai_clinic/features/setup/presentation/setup/widgets/working_hours_editor.dart';

import 'setup_widget_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WorkingHoursEditor', () {
    testWidgets('shows collapsed summary by default', (tester) async {
      await pumpSetupWidget(
        tester,
        child: WorkingHoursEditor(value: createDefaultWorkingDays(), onChange: (_) {}),
        scrollable: false,
      );
      await settleSetupWidget(tester);

      expect(find.text('Working days & hours'), findsOneWidget);
      expect(find.textContaining('days open'), findsOneWidget);
      expect(find.text('Monday'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('expands to show weekday rows when tapped', (tester) async {
      await pumpSetupWidget(
        tester,
        child: WorkingHoursEditor(value: createDefaultWorkingDays(), onChange: (_) {}),
        scrollable: false,
      );
      await settleSetupWidget(tester);

      await tester.tap(find.text('Working days & hours'));
      await settleSetupWidget(tester);

      expect(find.text('Monday'), findsOneWidget);
      expect(find.text('Sunday'), findsOneWidget);
    });

    testWidgets('calls onChange when a day is toggled', (tester) async {
      var latest = createDefaultWorkingDays();

      await pumpSetupWidget(
        tester,
        child: WorkingHoursEditor(value: latest, onChange: (days) => latest = days),
        scrollable: false,
      );
      await settleSetupWidget(tester);

      await tester.tap(find.text('Working days & hours'));
      await pumpSetupFrames(tester);
      drainSetupTestExceptions(tester);

      final mondayCheckbox = find.descendant(
        of: find.ancestor(of: find.text('Monday'), matching: find.byType(Row)),
        matching: find.byType(AppCheckbox),
      );
      await tester.ensureVisible(mondayCheckbox);
      final checkbox = tester.widget<AppCheckbox>(mondayCheckbox);
      checkbox.onChanged!(AppCheckboxState.unchecked);
      await pumpSetupFrames(tester);

      final monday = latest.firstWhere((day) => day.day == 'mon');
      expect(monday.enabled, isFalse);
    });

    testWidgets('shows time errors when expanded', (tester) async {
      await pumpSetupWidget(
        tester,
        child: WorkingHoursEditor(
          value: createDefaultWorkingDays(),
          onChange: (_) {},
          errors: const {'mon-time': 'Closing time must be after opening'},
        ),
        scrollable: false,
      );
      await pumpSetupFrames(tester);

      await tester.tap(find.text('Working days & hours'));
      await pumpSetupFrames(tester);

      expect(find.text('Monday'), findsOneWidget);
      expect(find.text('Closing time must be after opening'), findsOneWidget);
    });
  });
}
