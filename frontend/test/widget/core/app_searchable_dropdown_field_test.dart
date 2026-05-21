import 'package:ai_clinic/app/theme/app_theme.dart';
import 'package:ai_clinic/core/widgets/app_searchable_dropdown_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrap(Widget child) {
    return MaterialApp(
      theme: AppTheme.lightTheme(),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );
  }

  group('AppSearchableDropdownField', () {
    testWidgets('tapping a suggestion populates the field', (tester) async {
      final controller = TextEditingController();

      await tester.pumpWidget(
        wrap(
          AppSearchableDropdownField(
            label: 'Currency',
            controller: controller,
            options: const ['EGP', 'USD'],
            filterOptions: (query) {
              final q = query.trim().toUpperCase();
              return const ['EGP', 'USD'].where((code) => code.contains(q)).toList();
            },
          ),
        ),
      );

      await tester.tap(find.byType(TextFormField));
      await tester.pump();
      await tester.pump();

      expect(find.widgetWithText(ListTile, 'EGP'), findsOneWidget);

      await tester.tap(find.widgetWithText(ListTile, 'EGP'));
      await tester.pumpAndSettle();

      expect(controller.text, 'EGP');
    });

    testWidgets('tapping a suggestion in a scroll view populates the field', (tester) async {
      final controller = TextEditingController();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme(),
          home: Scaffold(
            body: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: AppSearchableDropdownField(
                    fieldKey: const ValueKey('bootstrap_currency'),
                    label: 'Currency code',
                    controller: controller,
                    options: const ['EGP', 'USD'],
                    filterOptions: (query) {
                      final q = query.trim().toUpperCase();
                      return const ['EGP', 'USD'].where((code) => code.contains(q)).toList();
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('bootstrap_currency')));
      await tester.pump();
      await tester.pump();

      await tester.enterText(find.byKey(const ValueKey('bootstrap_currency')), 'EG');
      await tester.pump();
      await tester.pump();

      await tester.tap(find.widgetWithText(ListTile, 'EGP'));
      await tester.pumpAndSettle();

      expect(controller.text, 'EGP');
    });
  });
}
