import 'package:ai_clinic/features/settings/presentation/models/settings_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SettingsScreens', () {
    test('all contains appearance, notifications, and security', () {
      final ids = SettingsScreens.all.map((screen) => screen.id).toList();

      expect(ids, containsAll(['appearance', 'notifications', 'security']));
      expect(SettingsScreens.all.length, 3);
    });

    test('defaultId is appearance', () {
      expect(SettingsScreens.defaultId, 'appearance');
    });

    group('byId', () {
      test('returns null for null input', () {
        expect(SettingsScreens.byId(null), isNull);
      });

      test('returns matching definition for known ids', () {
        expect(SettingsScreens.byId('appearance'), SettingsScreens.appearance);
        expect(SettingsScreens.byId('notifications'), SettingsScreens.notifications);
        expect(SettingsScreens.byId('security'), SettingsScreens.security);
      });

      test('returns null for unknown id', () {
        expect(SettingsScreens.byId('billing'), isNull);
      });
    });

    test('resolve falls back to appearance', () {
      expect(SettingsScreens.resolve(null), SettingsScreens.appearance);
      expect(SettingsScreens.resolve('unknown'), SettingsScreens.appearance);
      expect(SettingsScreens.resolve('security'), SettingsScreens.security);
    });

    test('routeFor builds settings sub-route paths', () {
      expect(SettingsScreens.routeFor('appearance'), '/settings/appearance');
      expect(SettingsScreens.routeFor('notifications'), '/settings/notifications');
      expect(SettingsScreens.routeFor('security'), '/settings/security');
    });
  });
}
