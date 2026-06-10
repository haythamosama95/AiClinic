import 'package:ai_clinic/app/shell/widgets/shell_content_panel.dart';
import 'package:ai_clinic/core/ui/theme/shadow_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'shell_test_support.dart';

void main() {
  group('ShellContentPanel', () {
    testWidgets('renders child inside panel', (tester) async {
      await pumpShellWidget(tester, child: const ShellContentPanel(child: Text('Content')));

      expect(find.text('Content'), findsOneWidget);
    });

    testWidgets('custom backgroundColor overrides default', (tester) async {
      await pumpShellWidget(
        tester,
        child: const ShellContentPanel(backgroundColor: Colors.red, child: SizedBox.shrink()),
      );

      final decoratedBox = tester.widget<DecoratedBox>(find.byType(DecoratedBox));
      final decoration = decoratedBox.decoration as BoxDecoration;
      expect(decoration.color, Colors.red);
    });

    testWidgets('applies card shadow', (tester) async {
      await pumpShellWidget(tester, child: const ShellContentPanel(child: SizedBox.shrink()));

      final decoratedBox = tester.widget<DecoratedBox>(find.byType(DecoratedBox));
      final decoration = decoratedBox.decoration as BoxDecoration;
      expect(decoration.boxShadow, ShadowTokens.card);
    });

    testWidgets('clips child to rounded rect', (tester) async {
      await pumpShellWidget(tester, child: const ShellContentPanel(child: SizedBox.shrink()));

      expect(find.byType(ClipRRect), findsOneWidget);
    });
  });
}
