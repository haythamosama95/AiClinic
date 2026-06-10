import 'package:ai_clinic/app/shell/config/shell_nav_config.dart';
import 'package:ai_clinic/app/shell/shell_tokens.dart';
import 'package:ai_clinic/app/shell/widgets/shell_nav.dart';
import 'package:ai_clinic/app/shell/widgets/shell_nav_item_row.dart';
import 'package:ai_clinic/app/shell/widgets/shell_nav_metrics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'shell_test_support.dart';

void main() {
  group('ShellNav', () {
    testWidgets('renders all ShellNavConfig.entries', (tester) async {
      await pumpShellNav(tester);

      expect(find.text('Dashboard'), findsOneWidget);
      expect(find.text('Appointments'), findsOneWidget);
    });

    testWidgets('renders dev options footer above collapse control', (tester) async {
      await pumpShellNav(tester);

      final devOptions = find.text('Dev Options');
      final collapse = shellNavCollapseControl();
      expect(devOptions, findsOneWidget);
      expect(collapse, findsOneWidget);
      expect(tester.getTopLeft(collapse).dy, greaterThan(tester.getTopLeft(devOptions).dy));
    });

    testWidgets('item tap calls onItemSelected', (tester) async {
      String? selectedId;
      await pumpShellNav(tester, onItemSelected: (id) => selectedId = id);

      await tester.tap(find.text('Dashboard'));
      await tester.pump();

      expect(selectedId, 'dashboard');
    });

    testWidgets('collapse control shows Collapse label when expanded', (tester) async {
      await pumpShellNav(tester);

      expect(shellNavCollapseControl(), findsOneWidget);
      expect(find.byIcon(Icons.chevron_left), findsOneWidget);
    });

    testWidgets('collapse toggle animates sidebar width toward collapsed width', (tester) async {
      await pumpShellNav(tester, settle: false);

      await tester.tap(shellNavCollapseControl());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 125));

      final animatedSizedBox = find.descendant(
        of: find.byType(ShellNav),
        matching: find.byWidgetPredicate((w) => w is SizedBox && w.width != null && w.width! < ShellTokens.navWidth),
      );
      expect(animatedSizedBox, findsWidgets);

      await tester.pumpAndSettle();

      final navSizedBox = tester.widget<SizedBox>(
        find
            .descendant(
              of: find.byType(ShellNav),
              matching: find.byWidgetPredicate((w) => w is SizedBox && w.width != null),
            )
            .first,
      );
      expect(navSizedBox.width, ShellTokens.navCollapsedWidth);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    });

    testWidgets('provides ShellNavMetrics to descendants', (tester) async {
      await pumpShellNav(tester, settle: false);

      await tester.tap(shellNavCollapseControl());
      await tester.pump();
      await tester.pump(ShellTokens.collapseDuration);

      final metrics = tester.widget<ShellNavMetrics>(find.byType(ShellNavMetrics));
      expect(metrics.collapseT, 1);
    });

    testWidgets('parent can expand group when child is selected', (tester) async {
      final expanded = <String>{};

      await pumpShellWidget(
        tester,
        child: StatefulBuilder(
          builder: (context, setState) {
            return ShellNav(
              selectedItemId: 'dashboard',
              expandedGroupIds: expanded,
              onItemSelected: (id) {
                setState(() {
                  final groupId = ShellNavConfig.groupIdFor(id);
                  if (groupId != null) expanded.add(groupId);
                });
              },
              onGroupToggled: (groupId) {
                setState(() {
                  if (expanded.contains(groupId)) {
                    expanded.remove(groupId);
                  } else {
                    expanded.add(groupId);
                  }
                });
              },
            );
          },
        ),
      );

      await tester.tap(find.text('Appointments'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ShellNavItemRow, 'Calendar'));
      await tester.pumpAndSettle();

      expect(expanded.contains('appointments'), isTrue);
    });

    testWidgets('aligns nav below header offset', (tester) async {
      await pumpShellNav(tester);

      final topSpacer = find.descendant(
        of: find.byType(ShellNav),
        matching: find.byWidgetPredicate(
          (w) => w is SizedBox && w.height == ShellTokens.headerHeight && w.width == null,
        ),
      );
      expect(topSpacer, findsOneWidget);
    });
  });
}
