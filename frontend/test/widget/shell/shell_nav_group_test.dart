import 'package:ai_clinic/app/shell/models/shell_nav_models.dart';
import 'package:ai_clinic/app/shell/shell_tokens.dart';
import 'package:ai_clinic/app/shell/widgets/shell_nav_group.dart';
import 'package:ai_clinic/app/shell/widgets/shell_nav_item_row.dart';
import 'package:ai_clinic/app/shell/widgets/shell_nav_metrics.dart';
import 'package:ai_clinic/app/shell/widgets/shell_nav_single_item.dart';
import 'package:ai_clinic/app/shell/widgets/shell_nav_tree_connector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'shell_test_support.dart';

const _appointmentsGroup = ShellNavGroup(
  id: 'appointments',
  label: 'Appointments',
  icon: Icons.calendar_month_outlined,
  children: [
    ShellNavSingle(id: 'appointments-calendar', label: 'Calendar', icon: Icons.calendar_view_month_outlined),
    ShellNavSingle(id: 'appointments-book', label: 'Book appointment', icon: Icons.event_available_outlined),
    ShellNavSingle(
      id: 'appointments-queue',
      label: 'Queue',
      icon: Icons.queue_outlined,
      badgeCount: 8,
      badgeTone: ShellNavBadgeTone.success,
    ),
  ],
);

Future<void> pumpShellNavGroup(
  WidgetTester tester, {
  bool isExpanded = true,
  String selectedItemId = 'appointments-calendar',
  void Function(String groupId)? onToggle,
  void Function(String itemId)? onSelected,
  double collapseT = 0,
  bool settle = true,
}) {
  return pumpShellWidget(
    tester,
    settle: settle,
    child: ShellNavMetrics(
      collapseT: collapseT,
      child: ShellNavGroupWidget(
        group: _appointmentsGroup,
        isExpanded: isExpanded,
        selectedItemId: selectedItemId,
        onToggle: onToggle ?? (_) {},
        onSelected: onSelected ?? (_) {},
      ),
    ),
  );
}

void main() {
  group('ShellNavGroupWidget', () {
    testWidgets('renders group header with label and icon', (tester) async {
      await pumpShellNavGroup(tester, isExpanded: false);

      expect(find.text('Appointments'), findsOneWidget);
      expect(find.byIcon(Icons.calendar_month_outlined), findsWidgets);
    });

    testWidgets('header tap calls onToggle with group id', (tester) async {
      String? toggledId;
      await pumpShellNavGroup(tester, isExpanded: false, onToggle: (id) => toggledId = id);

      await tester.tap(find.text('Appointments'));
      await tester.pump();

      expect(toggledId, 'appointments');
    });

    testWidgets('group header selected when child selected and group collapsed', (tester) async {
      await pumpShellNavGroup(tester, isExpanded: false, selectedItemId: 'appointments-queue');

      final headerRow = tester.widget<ShellNavItemRow>(
        find.ancestor(of: find.text('Appointments'), matching: find.byType(ShellNavItemRow)),
      );
      expect(headerRow.isSelected, isTrue);
    });

    testWidgets('group header not selected when expanded even if child selected', (tester) async {
      await pumpShellNavGroup(tester, isExpanded: true, selectedItemId: 'appointments-queue');

      final headerRows = tester.widgetList<ShellNavItemRow>(find.byType(ShellNavItemRow));
      final headerRow = headerRows.firstWhere((row) => row.label == 'Appointments');
      expect(headerRow.isSelected, isFalse);
    });

    testWidgets('expanded shows all child ShellNavSingleItem rows', (tester) async {
      await pumpShellNavGroup(tester, isExpanded: true);

      expect(find.text('Calendar'), findsOneWidget);
      expect(find.text('Book appointment'), findsOneWidget);
      expect(find.text('Queue'), findsOneWidget);
      expect(find.byType(ShellNavSingleItem), findsNWidgets(3));
    });

    testWidgets('collapsed clips child rows with zero heightFactor', (tester) async {
      await pumpShellNavGroup(tester, isExpanded: false);

      final align = tester.widget<Align>(
        find.descendant(of: find.byType(ShellNavGroupWidget), matching: find.byType(Align)),
      );
      expect(align.heightFactor, 0);
    });

    testWidgets('expand animates heightFactor from 0 to 1', (tester) async {
      final isExpanded = ValueNotifier(false);
      addTearDown(isExpanded.dispose);

      await pumpShellWidget(
        tester,
        settle: false,
        child: ShellNavMetrics(
          collapseT: 0,
          child: ValueListenableBuilder<bool>(
            valueListenable: isExpanded,
            builder: (context, expanded, _) {
              return ShellNavGroupWidget(
                group: _appointmentsGroup,
                isExpanded: expanded,
                selectedItemId: 'appointments-calendar',
                onToggle: (_) {},
                onSelected: (_) {},
              );
            },
          ),
        ),
      );
      await tester.pump();

      final collapsedAlign = tester.widget<Align>(
        find.descendant(of: find.byType(ShellNavGroupWidget), matching: find.byType(Align)),
      );
      expect(collapsedAlign.heightFactor, 0);

      isExpanded.value = true;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 125));

      final midAlign = tester.widget<Align>(
        find.descendant(of: find.byType(ShellNavGroupWidget), matching: find.byType(Align)),
      );
      expect(midAlign.heightFactor, greaterThan(0));
      expect(midAlign.heightFactor, lessThan(1));

      await tester.pump(ShellTokens.expandDuration);
      final settledAlign = tester.widget<Align>(
        find.descendant(of: find.byType(ShellNavGroupWidget), matching: find.byType(Align)),
      );
      expect(settledAlign.heightFactor, 1);
    });

    testWidgets('chevron rotates when expanded', (tester) async {
      await pumpShellNavGroup(tester, isExpanded: true);

      expect(
        find.descendant(of: find.byType(ShellNavGroupWidget), matching: find.byType(RotationTransition)),
        findsOneWidget,
      );
    });

    testWidgets('renders ShellNavTreeConnector for children', (tester) async {
      await pumpShellNavGroup(tester, isExpanded: true);

      final connector = tester.widget<ShellNavTreeConnector>(find.byType(ShellNavTreeConnector));
      expect(connector.childCount, 3);
    });

    testWidgets('shows icon-only header when nav collapsed', (tester) async {
      await pumpShellNavGroup(tester, isExpanded: true, collapseT: 1);

      expect(find.text('Appointments'), findsNothing);
      expect(find.byIcon(Icons.calendar_month_outlined), findsWidgets);
      expect(find.byIcon(Icons.keyboard_arrow_down), findsNothing);
    });
  });
}
