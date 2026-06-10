import 'package:ai_clinic/app/shell/models/shell_nav_models.dart';
import 'package:ai_clinic/app/shell/shell_tokens.dart';
import 'package:ai_clinic/app/shell/widgets/shell_nav_badge.dart';
import 'package:ai_clinic/app/shell/widgets/shell_nav_item_row.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'shell_test_support.dart';

void main() {
  group('ShellNavItemRow', () {
    testWidgets('renders icon and label', (tester) async {
      await pumpShellNavItemRow(tester, label: 'Dashboard', icon: Icons.dashboard_outlined);

      expect(find.text('Dashboard'), findsOneWidget);
      expect(find.byIcon(Icons.dashboard_outlined), findsOneWidget);
    });

    testWidgets('row height matches ShellTokens.itemHeight', (tester) async {
      await pumpShellNavItemRow(tester);

      final sizedBox = tester.widget<SizedBox>(
        find.descendant(of: find.byType(ShellNavItemRow), matching: find.byType(SizedBox)).first,
      );
      expect(sizedBox.height, ShellTokens.itemHeight);
    });

    testWidgets('tap invokes onTap', (tester) async {
      var tapped = false;
      await pumpShellNavItemRow(tester, onTap: () => tapped = true);

      await tester.tap(find.byType(ShellNavItemRow));
      await tester.pump();

      expect(tapped, isTrue);
    });

    testWidgets('selected state uses semibold label', (tester) async {
      await pumpShellNavItemRow(tester, isSelected: true);

      final text = tester.widget<Text>(find.text('Dashboard'));
      expect(text.style?.fontWeight, FontWeight.w600);
    });

    testWidgets('hover shows highlight pill via AnimatedOpacity', (tester) async {
      await pumpShellNavItemRow(tester, settle: false);

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);

      await gesture.moveTo(tester.getCenter(find.byType(ShellNavItemRow)));
      await tester.pump();

      final animatedOpacity = tester.widget<AnimatedOpacity>(
        find.descendant(of: find.byType(ShellNavItemRow), matching: find.byType(AnimatedOpacity)),
      );
      expect(animatedOpacity.opacity, greaterThan(0));
      expect(animatedOpacity.duration, ShellTokens.hoverDuration);
    });

    testWidgets('hover pill fades out on exit', (tester) async {
      await pumpShellNavItemRow(tester, settle: false);

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);

      final center = tester.getCenter(find.byType(ShellNavItemRow));
      await gesture.moveTo(center);
      await tester.pump();
      await tester.pump(ShellTokens.hoverDuration);

      await gesture.moveTo(const Offset(-100, -100));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));

      final animatedOpacity = tester.widget<AnimatedOpacity>(
        find.descendant(of: find.byType(ShellNavItemRow), matching: find.byType(AnimatedOpacity)),
      );
      expect(animatedOpacity.opacity, lessThan(1));
    });

    testWidgets('renders ShellNavBadge when badgeCount and badgeTone set', (tester) async {
      await pumpShellNavItemRow(tester, badgeCount: 3, badgeTone: ShellNavBadgeTone.warning);

      expect(find.byType(ShellNavBadge), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('renders trailing widget', (tester) async {
      await pumpShellNavItemRow(tester, trailing: const Icon(Icons.keyboard_arrow_down));

      expect(find.byIcon(Icons.keyboard_arrow_down), findsOneWidget);
    });

    testWidgets('label opacity fades with nav collapse progress', (tester) async {
      await pumpShellNavItemRow(tester, collapseT: 0.5);

      final opacity = tester.widget<Opacity>(
        find.descendant(of: find.byType(ShellNavItemRow), matching: find.byType(Opacity)),
      );
      expect(opacity.opacity, closeTo(0.5, 0.01));
    });

    testWidgets('badge dot appears on icon when collapsed past halfway', (tester) async {
      await pumpShellNavItemRow(tester, badgeCount: 5, badgeTone: ShellNavBadgeTone.success, collapseT: 0.6);

      final dot = find.descendant(
        of: find.byType(ShellNavItemRow),
        matching: find.byWidgetPredicate((widget) {
          if (widget is! Container) return false;
          final decoration = widget.decoration;
          return decoration is BoxDecoration && decoration.shape == BoxShape.circle;
        }),
      );
      expect(dot, findsOneWidget);
    });

    testWidgets('enablePointerEvents false skips GestureDetector', (tester) async {
      await pumpShellNavItemRow(tester, enablePointerEvents: false);

      expect(find.byType(GestureDetector), findsNothing);
    });

    testWidgets('hovered prop drives pill when pointer events disabled', (tester) async {
      await pumpShellNavItemRow(tester, enablePointerEvents: false, hovered: true);

      final animatedOpacity = tester.widget<AnimatedOpacity>(
        find.descendant(of: find.byType(ShellNavItemRow), matching: find.byType(AnimatedOpacity)),
      );
      expect(animatedOpacity.opacity, 1);
    });
  });
}
