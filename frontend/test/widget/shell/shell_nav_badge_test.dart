import 'package:ai_clinic/app/shell/models/shell_nav_models.dart';
import 'package:ai_clinic/app/shell/shell_tokens.dart';
import 'package:ai_clinic/app/shell/widgets/shell_nav_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'shell_test_support.dart';

void main() {
  group('ShellNavBadge', () {
    testWidgets('renders count text for positive count', (tester) async {
      await pumpShellWidget(tester, child: const ShellNavBadge(count: 8, tone: ShellNavBadgeTone.success));

      expect(find.text('8'), findsOneWidget);
    });

    testWidgets('renders nothing when count is zero', (tester) async {
      await pumpShellWidget(tester, child: const ShellNavBadge(count: 0, tone: ShellNavBadgeTone.neutral));

      expect(find.byType(ShellNavBadge), findsOneWidget);
      expect(find.text('0'), findsNothing);
      expect(find.byType(Container), findsNothing);
    });

    testWidgets('renders nothing when count is negative', (tester) async {
      await pumpShellWidget(tester, child: const ShellNavBadge(count: -1, tone: ShellNavBadgeTone.warning));

      expect(find.text('-1'), findsNothing);
      expect(find.byType(Container), findsNothing);
    });

    testWidgets('warning tone uses warning background token', (tester) async {
      await pumpShellWidget(tester, child: const ShellNavBadge(count: 3, tone: ShellNavBadgeTone.warning));

      final container = tester.widget<Container>(find.byType(Container));
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.color, ShellTokens.badgeWarningBackground);
    });

    testWidgets('success tone uses success background token', (tester) async {
      await pumpShellWidget(tester, child: const ShellNavBadge(count: 8, tone: ShellNavBadgeTone.success));

      final container = tester.widget<Container>(find.byType(Container));
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.color, ShellTokens.badgeSuccessBackground);
    });

    testWidgets('enforces minimum width constraint', (tester) async {
      await pumpShellWidget(tester, child: const ShellNavBadge(count: 1, tone: ShellNavBadgeTone.neutral));

      final container = tester.widget<Container>(find.byType(Container));
      expect(container.constraints, const BoxConstraints(minWidth: 22));
    });
  });
}
