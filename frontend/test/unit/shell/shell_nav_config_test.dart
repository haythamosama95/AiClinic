import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/navigation/login_query_params.dart';
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

    test('allows design system route for router bypass', () {
      expect(ShellNavConfig.allowsUnauthenticatedPreview(AppRoutes.foundationDemo), isTrue);
    });

    test('blocks auth and unknown routes', () {
      expect(ShellNavConfig.allowsUnauthenticatedPreview(AppRoutes.login), isFalse);
      expect(ShellNavConfig.allowsUnauthenticatedPreview(AppRoutes.bootstrap), isFalse);
      expect(ShellNavConfig.allowsUnauthenticatedPreview('/unknown'), isFalse);
    });
  });

  group('ShellNavConfig.shouldUseUnauthenticatedPreviewPlaceholder', () {
    test('uses placeholders for shell preview routes but not design system', () {
      expect(ShellNavConfig.shouldUseUnauthenticatedPreviewPlaceholder(AppRoutes.home), isTrue);
      expect(ShellNavConfig.shouldUseUnauthenticatedPreviewPlaceholder(AppRoutes.settingsGeneral), isTrue);
      expect(ShellNavConfig.shouldUseUnauthenticatedPreviewPlaceholder(AppRoutes.foundationDemo), isFalse);
    });
  });

  group('LoginQueryParams', () {
    test('forgot-password intent redirect preserves query contract', () {
      expect(
        LoginQueryParams.loginWithForgotPasswordIntent(),
        '${AppRoutes.login}?${LoginQueryParams.forgotPasswordQueryKey}=${LoginQueryParams.forgotPasswordQueryValue}',
      );
      expect(
        LoginQueryParams.isForgotPasswordIntent({
          LoginQueryParams.forgotPasswordQueryKey: LoginQueryParams.forgotPasswordQueryValue,
        }),
        isTrue,
      );
      expect(LoginQueryParams.isForgotPasswordIntent(const {}), isFalse);
    });
  });
}
