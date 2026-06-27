import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/core/ui/theme/forui_app_scope.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/buttons/app_button.dart';
import 'package:ai_clinic/core/ui/widgets/buttons/app_icon_button.dart';
import 'package:ai_clinic/core/ui/widgets/input/app_field_size.dart';
import 'package:ai_clinic/core/ui/widgets/layouts/app_notched_card.dart';
import 'package:ai_clinic/core/ui/widgets/layouts/notched_card_path.dart';

void main() {
  const cardWidth = 360.0;

  Future<void> pumpCard(
    WidgetTester tester, {
    Widget? title,
    Widget? description,
    required Widget body,
    List<Widget>? actions,
    TextDirection textDirection = TextDirection.ltr,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        builder: (context, child) => ForuiAppScope(child: child ?? const SizedBox.shrink()),
        home: Directionality(
          textDirection: textDirection,
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: cardWidth,
                child: AppNotchedCard(title: title, description: description, actions: actions, body: body),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('AppNotchedCard', () {
    testWidgets('renders title, description, and body', (tester) async {
      await pumpCard(
        tester,
        title: const Text('Panel title'),
        description: const Text('Panel description'),
        body: const Text('Panel body'),
      );

      expect(find.text('Panel title'), findsOneWidget);
      expect(find.text('Panel description'), findsOneWidget);
      expect(find.text('Panel body'), findsOneWidget);
    });

    testWidgets('reserves trailing header space so title does not overlap notch shelf', (tester) async {
      await pumpCard(
        tester,
        title: const Text('A very long dashboard panel title that should wrap within the leading width'),
        body: const Text('Body'),
      );

      final cardRect = tester.getRect(find.byType(AppNotchedCard));
      final cardTopLeft = tester.getTopLeft(find.byType(AppNotchedCard));
      final titleBottomRight = tester.getBottomRight(find.textContaining('very long dashboard'));
      final titleRightLocal = titleBottomRight.dx - cardTopLeft.dx;
      final shelf = NotchedCardPath.shelfRect(size: cardRect.size, borderRadius: 8, notchWidth: kNotchMinWidth);

      expect(titleRightLocal, lessThanOrEqualTo(shelf.left + 8));
    });

    testWidgets('uses minimum notch width when actions are omitted', (tester) async {
      await pumpCard(tester, body: const Text('Body'));

      final cardRect = tester.getRect(find.byType(AppNotchedCard));
      final shelf = NotchedCardPath.shelfRect(size: cardRect.size, borderRadius: 8, notchWidth: kNotchMinWidth);

      expect(shelf.width, closeTo(kNotchMinWidth, 0.01));
    });

    testWidgets('renders without title or description', (tester) async {
      await pumpCard(tester, body: const Text('Body only'));

      expect(find.text('Body only'), findsOneWidget);
      expect(find.byType(AppNotchedCard), findsOneWidget);
    });

    testWidgets('positions single action within notch shelf', (tester) async {
      await pumpCard(
        tester,
        body: const Text('Body'),
        actions: [AppIconButton(icon: const Icon(Icons.edit), tooltip: 'Edit', onPressed: () {})],
      );

      final cardRect = tester.getRect(find.byType(AppNotchedCard));
      final cardTopLeft = tester.getTopLeft(find.byType(AppNotchedCard));
      final clipper =
          tester
                  .widget<ClipPath>(find.descendant(of: find.byType(AppNotchedCard), matching: find.byType(ClipPath)))
                  .clipper!
              as NotchedCardClipper;
      final actionShell = tester.getRect(
        find.descendant(of: find.byType(AppNotchedCard), matching: find.byType(InkWell)).first,
      );
      final notchWidth = computeNotchWidth(
        cardWidth: cardRect.width,
        borderRadius: 8,
        actionsRowWidth: actionShell.width,
        shelfDepth: clipper.shelfDepth,
      );
      final shelf = NotchedCardPath.shelfRect(
        size: cardRect.size,
        borderRadius: 8,
        notchWidth: notchWidth,
        shelfDepth: clipper.shelfDepth,
      );

      expect(actionShell.center.dx - cardTopLeft.dx, closeTo(shelf.left + shelf.width / 2, 4));
      expect(actionShell.top - cardTopLeft.dy, greaterThanOrEqualTo(shelf.top - 1));
      expect(actionShell.bottom - cardTopLeft.dy, lessThanOrEqualTo(shelf.bottom + 1));
    });

    testWidgets('expands shelf depth for taller actions', (tester) async {
      await pumpCard(
        tester,
        body: const Text('Body'),
        actions: [AppIconButton(icon: const Icon(Icons.edit), tooltip: 'Edit', onPressed: () {})],
      );

      final iconClipper =
          tester
                  .widget<ClipPath>(find.descendant(of: find.byType(AppNotchedCard), matching: find.byType(ClipPath)))
                  .clipper!
              as NotchedCardClipper;

      await pumpCard(
        tester,
        body: const Text('Body'),
        actions: [
          AppButton(
            label: 'Last 6 months',
            icon: const Icon(Icons.expand_more, size: 18),
            variant: AppButtonVariant.ghost,
            size: AppFieldSize.md,
            onPressed: () {},
          ),
        ],
      );

      final tallClipper =
          tester
                  .widget<ClipPath>(find.descendant(of: find.byType(AppNotchedCard), matching: find.byType(ClipPath)))
                  .clipper!
              as NotchedCardClipper;

      expect(tallClipper.shelfDepth, greaterThan(iconClipper.shelfDepth));
      expect(tallClipper.shelfDepth, greaterThan(kNotchShelfDepth));
    });

    testWidgets('uses SpacingTokens.sm between multiple action containers', (tester) async {
      await pumpCard(
        tester,
        body: const Text('Body'),
        actions: [
          AppIconButton(icon: const Icon(Icons.edit), tooltip: 'Edit', onPressed: () {}),
          AppIconButton(icon: const Icon(Icons.delete), tooltip: 'Delete', onPressed: () {}),
        ],
      );

      final shells = find.descendant(of: find.byType(AppNotchedCard), matching: find.byType(InkWell));
      final editShell = tester.getRect(shells.at(0));
      final deleteShell = tester.getRect(shells.at(1));

      expect(deleteShell.left - editShell.right, closeTo(SpacingTokens.sm, 1));
    });

    testWidgets('expands notch width for multiple actions', (tester) async {
      await pumpCard(
        tester,
        body: const Text('Body'),
        actions: [AppIconButton(icon: const Icon(Icons.edit), tooltip: 'Edit', onPressed: () {})],
      );

      final singleCardRect = tester.getRect(find.byType(AppNotchedCard));
      final singleShelf = NotchedCardPath.shelfRect(
        size: singleCardRect.size,
        borderRadius: 8,
        notchWidth: computeNotchWidth(
          cardWidth: singleCardRect.width,
          borderRadius: 8,
          actionsRowWidth: tester.getRect(find.byTooltip('Edit')).width,
        ),
      );

      await pumpCard(
        tester,
        body: const Text('Body'),
        actions: [
          AppIconButton(icon: const Icon(Icons.edit), tooltip: 'Edit', onPressed: () {}),
          AppIconButton(icon: const Icon(Icons.delete), tooltip: 'Delete', onPressed: () {}),
          AppIconButton(icon: const Icon(Icons.share), tooltip: 'Share', onPressed: () {}),
        ],
      );

      final multiCardRect = tester.getRect(find.byType(AppNotchedCard));
      final shells = find.descendant(of: find.byType(AppNotchedCard), matching: find.byType(InkWell));
      final firstShell = tester.getRect(shells.at(0));
      final lastShell = tester.getRect(shells.at(2));
      final actionsRowWidth = lastShell.right - firstShell.left;
      final multiShelf = NotchedCardPath.shelfRect(
        size: multiCardRect.size,
        borderRadius: 8,
        notchWidth: computeNotchWidth(
          cardWidth: multiCardRect.width,
          borderRadius: 8,
          actionsRowWidth: actionsRowWidth,
        ),
      );

      expect(multiShelf.width, greaterThan(singleShelf.width));

      final editShell = tester.getRect(shells.at(0));
      final deleteShell = tester.getRect(shells.at(1));
      expect(deleteShell.left - editShell.right, closeTo(SpacingTokens.sm, 1));
    });

    testWidgets('does not clip tall text and icon action row', (tester) async {
      await pumpCard(
        tester,
        title: const Text('Billing overview'),
        description: const Text('Collections and adjustments'),
        body: const Text('Body'),
        actions: [
          AppButton(
            label: 'Last 6 months',
            icon: const Icon(Icons.expand_more, size: 18),
            variant: AppButtonVariant.ghost,
            size: AppFieldSize.sm,
            onPressed: () {},
          ),
          AppIconButton(icon: const Icon(Icons.filter_list_outlined), tooltip: 'Filter billing', onPressed: () {}),
        ],
      );

      final cardTopLeft = tester.getTopLeft(find.byType(AppNotchedCard));
      final clipper =
          tester
                  .widget<ClipPath>(find.descendant(of: find.byType(AppNotchedCard), matching: find.byType(ClipPath)))
                  .clipper!
              as NotchedCardClipper;
      final shells = find.descendant(of: find.byType(AppNotchedCard), matching: find.byType(InkWell));
      final firstShell = tester.getRect(shells.first);
      final lastShell = tester.getRect(shells.last);

      expect(find.text('Last 6 months'), findsOneWidget);
      expect(lastShell.bottom - cardTopLeft.dy, lessThanOrEqualTo(clipper.shelfDepth + 1));
      expect(firstShell.top - cardTopLeft.dy, greaterThanOrEqualTo(-1));
    });

    testWidgets('clips overflowing actions at card boundary', (tester) async {
      const narrowWidth = 120.0;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          builder: (context, child) => ForuiAppScope(child: child ?? const SizedBox.shrink()),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: narrowWidth,
                child: AppNotchedCard(
                  body: const Text('Body'),
                  actions: [
                    AppIconButton(icon: const Icon(Icons.edit), tooltip: 'Edit', onPressed: () {}),
                    AppIconButton(icon: const Icon(Icons.delete), tooltip: 'Delete', onPressed: () {}),
                    AppIconButton(icon: const Icon(Icons.share), tooltip: 'Share', onPressed: () {}),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      final cardRect = tester.getRect(find.byType(AppNotchedCard));
      final shareRect = tester.getRect(find.byTooltip('Share'));

      expect(shareRect.right, greaterThan(cardRect.right - 1));
      expect(shareRect.left, lessThan(cardRect.right));
    });

    testWidgets('mirrors notch shelf to leading top in RTL', (tester) async {
      await pumpCard(
        tester,
        textDirection: TextDirection.rtl,
        title: const Text('RTL panel title'),
        body: const Text('Body'),
      );

      final cardRect = tester.getRect(find.byType(AppNotchedCard));
      final clipper =
          tester
                  .widget<ClipPath>(find.descendant(of: find.byType(AppNotchedCard), matching: find.byType(ClipPath)))
                  .clipper!
              as NotchedCardClipper;
      final shelf = NotchedCardPath.shelfRect(
        size: cardRect.size,
        borderRadius: 8,
        notchWidth: kNotchMinWidth,
        textDirection: TextDirection.rtl,
      );

      expect(clipper.textDirection, TextDirection.rtl);
      expect(shelf.center.dx, lessThan(cardRect.width / 2));
    });

    testWidgets('positions actions in mirrored RTL shelf', (tester) async {
      await pumpCard(
        tester,
        textDirection: TextDirection.rtl,
        body: const Text('Body'),
        actions: [AppIconButton(icon: const Icon(Icons.edit), tooltip: 'Edit', onPressed: () {})],
      );

      final cardRect = tester.getRect(find.byType(AppNotchedCard));
      final cardTopLeft = tester.getTopLeft(find.byType(AppNotchedCard));
      final clipper =
          tester
                  .widget<ClipPath>(find.descendant(of: find.byType(AppNotchedCard), matching: find.byType(ClipPath)))
                  .clipper!
              as NotchedCardClipper;
      final actionShell = tester.getRect(
        find.descendant(of: find.byType(AppNotchedCard), matching: find.byType(InkWell)).first,
      );
      final notchWidth = computeNotchWidth(
        cardWidth: cardRect.width,
        borderRadius: 8,
        actionsRowWidth: actionShell.width,
        shelfDepth: clipper.shelfDepth,
      );
      final shelf = NotchedCardPath.shelfRect(
        size: cardRect.size,
        borderRadius: 8,
        notchWidth: notchWidth,
        shelfDepth: clipper.shelfDepth,
        textDirection: TextDirection.rtl,
      );

      expect(find.byType(PositionedDirectional), findsWidgets);
      expect(actionShell.center.dx - cardTopLeft.dx, closeTo(shelf.left + shelf.width / 2, 4));
      expect(actionShell.top - cardTopLeft.dy, greaterThanOrEqualTo(shelf.top - 1));
      expect(actionShell.bottom - cardTopLeft.dy, lessThanOrEqualTo(shelf.bottom + 1));
    });

    testWidgets('reserves trailing header space in RTL so title avoids notch shelf', (tester) async {
      await pumpCard(
        tester,
        textDirection: TextDirection.rtl,
        title: const Text('A very long dashboard panel title that should wrap within the leading width'),
        body: const Text('Body'),
      );

      final cardRect = tester.getRect(find.byType(AppNotchedCard));
      final cardTopLeft = tester.getTopLeft(find.byType(AppNotchedCard));
      final titleBottomLeft = tester.getBottomLeft(find.textContaining('very long dashboard'));
      final titleLeftLocal = titleBottomLeft.dx - cardTopLeft.dx;
      final shelf = NotchedCardPath.shelfRect(
        size: cardRect.size,
        borderRadius: 8,
        notchWidth: kNotchMinWidth,
        textDirection: TextDirection.rtl,
      );

      expect(titleLeftLocal, greaterThanOrEqualTo(shelf.right - 8));
    });
  });
}
