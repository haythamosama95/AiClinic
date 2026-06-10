import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/shell/config/shell_nav_config.dart';
import 'package:ai_clinic/app/shell/dev/shell_dev_nav.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ShellNavConfig', () {
    test('routeFor returns path for wired items', () {
      expect(ShellNavConfig.routeFor('dashboard'), AppRoutes.home);
      expect(ShellNavConfig.routeFor('appointments-calendar'), AppRoutes.appointmentsCalendar);
      expect(ShellNavConfig.routeFor('appointments-book'), AppRoutes.appointmentsBook);
      expect(ShellNavConfig.routeFor('appointments-queue'), AppRoutes.appointmentsQueue);
      expect(ShellNavConfig.routeFor(ShellDevNav.themeShowcaseId), AppRoutes.foundationDemo);
    });

    test('routeFor returns null for unknown id', () {
      expect(ShellNavConfig.routeFor('unknown-item'), isNull);
    });

    test('itemIdForLocation resolves exact paths', () {
      expect(ShellNavConfig.itemIdForLocation(AppRoutes.home), 'dashboard');
      expect(ShellNavConfig.itemIdForLocation(AppRoutes.appointmentsCalendar), 'appointments-calendar');
      expect(ShellNavConfig.itemIdForLocation(AppRoutes.appointmentsBook), 'appointments-book');
      expect(ShellNavConfig.itemIdForLocation(AppRoutes.appointmentsQueue), 'appointments-queue');
      expect(ShellNavConfig.itemIdForLocation(AppRoutes.foundationDemo), ShellDevNav.themeShowcaseId);
    });

    test('itemIdForLocation returns null for unrelated path', () {
      expect(ShellNavConfig.itemIdForLocation(AppRoutes.settings), isNull);
    });

    test('labelFor resolves top-level single', () {
      expect(ShellNavConfig.labelFor('dashboard'), 'Dashboard');
    });

    test('labelFor resolves group child', () {
      expect(ShellNavConfig.labelFor('appointments-queue'), 'Queue');
    });

    test('labelFor resolves dev theme showcase item', () {
      expect(ShellNavConfig.labelFor(ShellDevNav.themeShowcaseId), 'Theme Showcase');
    });

    test('labelFor returns null for unknown id', () {
      expect(ShellNavConfig.labelFor('missing'), isNull);
    });

    test('groupIdFor returns appointments for child items', () {
      expect(ShellNavConfig.groupIdFor('appointments-calendar'), 'appointments');
      expect(ShellNavConfig.groupIdFor('appointments-book'), 'appointments');
      expect(ShellNavConfig.groupIdFor('appointments-queue'), 'appointments');
    });

    test('groupIdFor returns null for top-level single', () {
      expect(ShellNavConfig.groupIdFor('dashboard'), isNull);
    });

    test('defaultSelectedId returns first entry id', () {
      expect(ShellNavConfig.defaultSelectedId(), 'dashboard');
    });

    test('defaultExpandedGroupIds is empty when default is top-level', () {
      expect(ShellNavConfig.defaultExpandedGroupIds(), isEmpty);
    });
  });
}
