import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/core/ui/components/app_filter_menu_panel.dart';
import 'package:ai_clinic/core/ui/components/app_popover.dart';
import 'package:ai_clinic/core/ui/theme/app_theme.dart';

void main() {
  testWidgets('AppFilterMenuPanel allows switching status while popover stays open', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 600));

    var selected = 'all';

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Center(
            child: StatefulBuilder(
              builder: (context, setState) {
                return AppPopover(
                  matchTriggerWidth: false,
                  width: 240,
                  triggerBuilder: (context, isOpen, onToggle) {
                    return ElevatedButton(onPressed: onToggle, child: const Text('Filter'));
                  },
                  child: AppFilterMenuPanel(
                    sections: [
                      AppFilterMenuSection(
                        id: 'status',
                        label: 'Status',
                        value: selected,
                        options: const [
                          AppFilterMenuOption(value: 'all', label: 'All statuses'),
                          AppFilterMenuOption(value: 'draft', label: 'Draft'),
                          AppFilterMenuOption(value: 'issued', label: 'Issued'),
                          AppFilterMenuOption(value: 'paid', label: 'Paid'),
                        ],
                        onChange: (value) => setState(() => selected = value),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Filter'));
    await tester.pumpAndSettle();

    expect(find.text('Draft'), findsOneWidget);

    await tester.tap(find.text('Draft'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(selected, 'draft');
    expect(find.text('Draft'), findsOneWidget);

    await tester.tap(find.text('Issued'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(selected, 'issued');
  });
}
