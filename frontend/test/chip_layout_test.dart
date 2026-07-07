import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_clinic/core/ui/components/app_chip.dart';
import 'package:ai_clinic/core/ui/theme/app_theme.dart';

void main() {
  testWidgets('selectable chip sizes in 140px Wrap', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SizedBox(
            width: 140,
            child: Wrap(
              spacing: 8,
              children: [
                AppChip(selectable: true, selected: true, onSelect: () {}, child: const Text('Today')),
                AppChip(selectable: true, onSelect: () {}, child: const Text('This week')),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final chips = tester.getSize(find.byType(AppChip).first);
    final chipsAll = find.byType(AppChip);
    print('chip count=${chipsAll.evaluate().length}');
    for (var i = 0; i < chipsAll.evaluate().length; i++) {
      print('chip $i size=${tester.getSize(chipsAll.at(i))} pos=${tester.getTopLeft(chipsAll.at(i))}');
    }
  });
}
