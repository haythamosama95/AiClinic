import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/core/ui/theme/forui_app_scope.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/settings/presentation/widgets/settings_section_card.dart';

void main() {
  group('SettingsSectionCard', () {
    Future<void> pumpCard(
      WidgetTester tester, {
      required bool isEditing,
      VoidCallback? onEdit,
      VoidCallback? onSave,
      VoidCallback? onCancel,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          builder: (context, child) => ForuiAppScope(child: child ?? const SizedBox.shrink()),
          home: Scaffold(
            body: SettingsSectionCard(
              title: 'Organization',
              isEditing: isEditing,
              onEdit: onEdit,
              onSave: onSave,
              onCancel: onCancel,
              child: const Text('Body'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('shows edit icon in header when not editing', (tester) async {
      await pumpCard(tester, isEditing: false, onEdit: () {});

      expect(find.byTooltip('Edit'), findsOneWidget);
      expect(find.widgetWithText(AppButton, 'Save'), findsNothing);
      expect(find.widgetWithText(AppButton, 'Cancel'), findsNothing);
    });

    testWidgets('shows save and cancel in header when editing', (tester) async {
      await pumpCard(tester, isEditing: true, onEdit: () {}, onSave: () {}, onCancel: () {});

      expect(find.byTooltip('Edit'), findsNothing);
      expect(find.widgetWithText(AppButton, 'Save'), findsOneWidget);
      expect(find.widgetWithText(AppButton, 'Cancel'), findsOneWidget);
    });

    testWidgets('omits header actions when edit callbacks are not provided', (tester) async {
      await pumpCard(tester, isEditing: false);

      expect(find.byTooltip('Edit'), findsNothing);
      expect(find.widgetWithText(AppButton, 'Save'), findsNothing);
    });
  });
}
