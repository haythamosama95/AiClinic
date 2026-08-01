import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/features/settings/presentation/components/settings_screen_primitives.dart';

import 'settings_widget_test_harness.dart';

void main() {
  group('SettingsScreenScaffold', () {
    testWidgets('stacks header and panel vertically', (tester) async {
      await pumpSettingsWidget(
        tester,
        child: const SettingsScreenScaffold(
          header: Text('Header stub'),
          panel: Text('Panel stub'),
        ),
      );
      await pumpSettingsFrames(tester);

      expect(find.text('Header stub'), findsOneWidget);
      expect(find.text('Panel stub'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('SettingsScreenHeader', () {
    testWidgets('shows title and description', (tester) async {
      await pumpSettingsWidget(
        tester,
        child: const SettingsScreenHeader(
          icon: Icons.settings_outlined,
          title: 'Test settings',
          description: 'Test description copy',
        ),
      );
      await pumpSettingsFrames(tester);

      expect(find.text('Test settings'), findsOneWidget);
      expect(find.text('Test description copy'), findsOneWidget);
      expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
    });

    testWidgets('shows optional action widget', (tester) async {
      await pumpSettingsWidget(
        tester,
        child: const SettingsScreenHeader(
          icon: Icons.settings_outlined,
          title: 'With action',
          description: 'Has trailing action',
          action: Text('Save'),
        ),
      );
      await pumpSettingsFrames(tester);

      expect(find.text('Save'), findsOneWidget);
    });
  });

  group('SettingsContentPanel', () {
    testWidgets('wraps child content', (tester) async {
      await pumpSettingsWidget(
        tester,
        child: const SettingsContentPanel(child: Text('Panel body')),
      );
      await pumpSettingsFrames(tester);

      expect(find.byType(SettingsContentPanel), findsOneWidget);
      expect(find.text('Panel body'), findsOneWidget);
    });
  });

  group('SettingsSettingRow', () {
    testWidgets('shows title, description, and control', (tester) async {
      await pumpSettingsWidget(
        tester,
        child: SettingsSettingRow(
          title: 'Row title',
          description: 'Row description',
          control: Switch(value: true, onChanged: (_) {}),
        ),
      );
      await pumpSettingsFrames(tester);

      expect(find.text('Row title'), findsOneWidget);
      expect(find.text('Row description'), findsOneWidget);
      expect(find.byType(Switch), findsOneWidget);
    });

    testWidgets('omits description when not provided', (tester) async {
      await pumpSettingsWidget(
        tester,
        child: SettingsSettingRow(
          title: 'Title only',
          control: const Text('Control'),
        ),
      );
      await pumpSettingsFrames(tester);

      expect(find.text('Title only'), findsOneWidget);
      expect(find.text('Control'), findsOneWidget);
    });
  });

  group('SettingsDividedRows', () {
    testWidgets('renders children separated by dividers', (tester) async {
      await pumpSettingsWidget(
        tester,
        child: const SettingsDividedRows(
          children: [
            Text('First row'),
            Text('Second row'),
            Text('Third row'),
          ],
        ),
      );
      await pumpSettingsFrames(tester);

      expect(find.text('First row'), findsOneWidget);
      expect(find.text('Second row'), findsOneWidget);
      expect(find.text('Third row'), findsOneWidget);
      expect(find.byType(Divider), findsNWidgets(2));
    });
  });
}
