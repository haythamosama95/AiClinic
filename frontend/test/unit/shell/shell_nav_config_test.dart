import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/shell/navigation/shell_nav_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ShellNavConfig.allowsUnauthenticatedPreview', () {
    test('allows clinic shell placeholder routes without login', () {
      expect(ShellNavConfig.allowsUnauthenticatedPreview(AppRoutes.home), isTrue);
      expect(ShellNavConfig.allowsUnauthenticatedPreview(AppRoutes.dashboard), isTrue);
      expect(ShellNavConfig.allowsUnauthenticatedPreview(AppRoutes.patients), isTrue);
      expect(ShellNavConfig.allowsUnauthenticatedPreview(AppRoutes.appointments), isTrue);
      expect(ShellNavConfig.allowsUnauthenticatedPreview(AppRoutes.settings), isTrue);
      expect(ShellNavConfig.allowsUnauthenticatedPreview(AppRoutes.billing), isTrue);
    });

    test('blocks auth and unknown routes', () {
      expect(ShellNavConfig.allowsUnauthenticatedPreview(AppRoutes.login), isFalse);
      expect(ShellNavConfig.allowsUnauthenticatedPreview(AppRoutes.bootstrap), isFalse);
      expect(ShellNavConfig.allowsUnauthenticatedPreview('/unknown'), isFalse);
    });
  });
}
