import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/core/ui/theme/forui_app_scope.dart';
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
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        builder: (context, child) => ForuiAppScope(child: child ?? const SizedBox.shrink()),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: cardWidth,
              child: AppNotchedCard(title: title, description: description, actions: actions, body: body),
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

      expect(titleRightLocal, lessThanOrEqualTo(shelf.left + 1));
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
  });
}
