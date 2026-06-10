import 'package:ai_clinic/app/shell/shell_tokens.dart';
import 'package:ai_clinic/app/shell/widgets/shell_nav_tree_connector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'shell_test_support.dart';

void main() {
  group('ShellNavTreeConnector', () {
    testWidgets('renders nothing when childCount is zero', (tester) async {
      await pumpShellWidget(tester, child: const ShellNavTreeConnector(childCount: 0));

      expect(find.descendant(of: find.byType(ShellNavTreeConnector), matching: find.byType(CustomPaint)), findsNothing);
    });

    testWidgets('sizes to childCount times item height', (tester) async {
      await pumpShellWidget(tester, child: const ShellNavTreeConnector(childCount: 3));

      final sizedBox = tester.widget<SizedBox>(find.byType(SizedBox).first);
      expect(sizedBox.width, 28);
      expect(sizedBox.height, 3 * ShellTokens.itemHeight);
    });

    testWidgets('uses CustomPaint for tree lines', (tester) async {
      await pumpShellWidget(tester, child: const ShellNavTreeConnector(childCount: 2));

      expect(
        find.descendant(of: find.byType(ShellNavTreeConnector), matching: find.byType(CustomPaint)),
        findsOneWidget,
      );
    });
  });
}
