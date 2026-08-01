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
      expect(ShellNavConfig.allowsUnauthenticatedPreview(AppRoutes.billingInvoices), isTrue);
    });

    test('allows design system route for router bypass', () {
      expect(ShellNavConfig.allowsUnauthenticatedPreview(AppRoutes.foundationDemo), isTrue);
    });

    test('blocks auth and unknown routes', () {
      expect(ShellNavConfig.allowsUnauthenticatedPreview(AppRoutes.login), isFalse);
      expect(ShellNavConfig.allowsUnauthenticatedPreview(AppRoutes.bootstrap), isFalse);
      expect(ShellNavConfig.allowsUnauthenticatedPreview('/unknown'), isFalse);
<<<<<<< HEAD
=======
    });
  });

  group('ShellNavConfig.shouldUseUnauthenticatedPreviewPlaceholder', () {
    test('uses placeholders for shell preview routes but not design system', () {
      expect(ShellNavConfig.shouldUseUnauthenticatedPreviewPlaceholder(AppRoutes.home), isTrue);
      expect(ShellNavConfig.shouldUseUnauthenticatedPreviewPlaceholder(AppRoutes.settings), isTrue);
      expect(ShellNavConfig.shouldUseUnauthenticatedPreviewPlaceholder(AppRoutes.foundationDemo), isFalse);
    });
  });

  group('ShellNavConfig.isFullWidthLocation', () {
    test('appointment detail uses full-width shell layout', () {
      expect(ShellNavConfig.isFullWidthLocation(AppRoutes.appointmentDetail('apt-1')), isTrue);
>>>>>>> master
    });
  });

<<<<<<< HEAD
  group('ShellNavConfig.shouldUseUnauthenticatedPreviewPlaceholder', () {
    test('uses placeholders for shell preview routes but not design system', () {
      expect(ShellNavConfig.shouldUseUnauthenticatedPreviewPlaceholder(AppRoutes.home), isTrue);
      expect(ShellNavConfig.shouldUseUnauthenticatedPreviewPlaceholder(AppRoutes.settings), isTrue);
      expect(ShellNavConfig.shouldUseUnauthenticatedPreviewPlaceholder(AppRoutes.foundationDemo), isFalse);
=======
    test('appointment hub routes stay full width', () {
      expect(ShellNavConfig.isFullWidthLocation(AppRoutes.appointmentsCalendar), isTrue);
      expect(ShellNavConfig.isFullWidthLocation(AppRoutes.appointmentsQueue), isTrue);
>>>>>>> master
    });
  });

<<<<<<< HEAD
=======
    test('non-detail appointment routes are not treated as detail', () {
      expect(ShellNavConfig.isFullWidthLocation(AppRoutes.appointmentsBook), isFalse);
      expect(ShellNavConfig.isFullWidthLocation(AppRoutes.appointmentsSchedule('doc-1')), isFalse);
    });
  });

>>>>>>> master
  group('ShellNavConfig.isFillViewportLocation', () {
    test('billing routes fill the shell viewport', () {
      expect(ShellNavConfig.isFillViewportLocation(AppRoutes.billingInvoices), isTrue);
      expect(ShellNavConfig.isFillViewportLocation(AppRoutes.billingInvoiceDetail('inv-1')), isTrue);
      expect(ShellNavConfig.isFillViewportLocation(AppRoutes.billingVisit('visit-1')), isTrue);
      expect(ShellNavConfig.isFillViewportLocation(AppRoutes.patients), isFalse);
    });
  });

<<<<<<< HEAD
=======
    test('personal settings routes use shell scroll (content-sized)', () {
      expect(ShellNavConfig.isFillViewportLocation(AppRoutes.settingsAppearance), isFalse);
      expect(ShellNavConfig.isFillViewportLocation(AppRoutes.settingsNotifications), isFalse);
      expect(ShellNavConfig.isFillViewportLocation(AppRoutes.settingsSecurity), isFalse);
      expect(ShellNavConfig.isFillViewportLocation(AppRoutes.settingsOrganization), isFalse);
    });
  });

  group('ShellNavConfig.itemIdForLocation', () {
    test('maps pushed visit billing routes to invoices nav item', () {
      expect(ShellNavConfig.itemIdForLocation(AppRoutes.billingVisit('visit-1')), 'invoices');
    });
  });

  group('ShellNavConfig.shellPageKeyForLocation', () {
    test('personal settings sub-routes share stable shell page key', () {
      expect(ShellNavConfig.shellPageKeyForLocation(AppRoutes.settingsAppearance), AppRoutes.settings);
      expect(ShellNavConfig.shellPageKeyForLocation(AppRoutes.settingsNotifications), AppRoutes.settings);
      expect(ShellNavConfig.shellPageKeyForLocation(AppRoutes.settingsSecurity), AppRoutes.settings);
    });

    test('other routes keep location as shell page key', () {
      expect(ShellNavConfig.shellPageKeyForLocation(AppRoutes.home), AppRoutes.home);
      expect(ShellNavConfig.shellPageKeyForLocation(AppRoutes.patients), AppRoutes.patients);
      expect(ShellNavConfig.shellPageKeyForLocation(AppRoutes.clinicManagement), AppRoutes.clinicManagement);
    });
  });

>>>>>>> master
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
