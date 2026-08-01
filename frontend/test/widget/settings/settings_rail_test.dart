import 'dart:ui' show Tristate;

import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/features/settings/presentation/components/settings_rail.dart';
import 'package:ai_clinic/features/settings/presentation/models/settings_screen.dart';

import 'settings_widget_test_harness.dart';

void main() {
  group('SettingsRail', () {
    testWidgets('renders all section labels at wide width', (tester) async {
      await pumpSettingsWidget(
        tester,
        surfaceSize: settingsWideSurfaceSize,
        child: SettingsRail(
          activeScreenId: SettingsScreens.defaultId,
          onNavigate: (_) {},
        ),
      );
      await pumpSettingsFrames(tester);

      expect(find.text('Appearance'), findsOneWidget);
      expect(find.text('Notifications'), findsOneWidget);
      expect(find.text('Security'), findsOneWidget);
      expect(find.text('SECTIONS'), findsOneWidget);
    });

    testWidgets('tapping section calls onNavigate with correct route', (tester) async {
      final routes = <String>[];

      await pumpSettingsWidget(
        tester,
        surfaceSize: settingsWideSurfaceSize,
        child: SettingsRail(
          activeScreenId: SettingsScreens.defaultId,
          onNavigate: routes.add,
        ),
      );
      await pumpSettingsFrames(tester);

      await tester.tap(find.text('Notifications'));
      await pumpSettingsFrames(tester);
      expect(routes, [SettingsScreens.routeFor('notifications')]);

      await tester.tap(find.text('Security'));
      await pumpSettingsFrames(tester);
      expect(routes, [
        SettingsScreens.routeFor('notifications'),
        SettingsScreens.routeFor('security'),
      ]);
    });

    testWidgets('active section is indicated via semantics selected state', (tester) async {
      await pumpSettingsWidget(
        tester,
        surfaceSize: settingsWideSurfaceSize,
        child: SettingsRail(
          activeScreenId: 'security',
          onNavigate: (_) {},
        ),
      );
      await pumpSettingsFrames(tester);

      final appearanceSemantics = tester.getSemantics(find.text('Appearance'));
      final securitySemantics = tester.getSemantics(find.text('Security'));

      expect(appearanceSemantics.flagsCollection.isSelected, Tristate.isFalse);
      expect(securitySemantics.flagsCollection.isSelected, Tristate.isTrue);
    });

    testWidgets('renders section labels in narrow horizontal layout', (tester) async {
      await pumpSettingsWidget(
        tester,
        surfaceSize: settingsNarrowSurfaceSize,
        child: SettingsRail(
          activeScreenId: SettingsScreens.defaultId,
          onNavigate: (_) {},
        ),
      );
      await pumpSettingsFrames(tester);

      expect(find.text('Appearance'), findsOneWidget);
      expect(find.text('Notifications'), findsOneWidget);
      expect(find.text('Security'), findsOneWidget);
      expect(find.text('SECTIONS'), findsNothing);
    });
  });
}
