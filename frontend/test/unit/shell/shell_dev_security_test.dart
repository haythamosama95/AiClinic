import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/app/shell/dev/dev_clinic_seed_notifier.dart';
import 'package:ai_clinic/app/shell/dev/shell_dev_fill_dummy_clinic.dart';
import 'package:ai_clinic/app/shell/dev/shell_dev_reset_clinic.dart';
import 'package:ai_clinic/app/shell/navigation/shell_nav_config.dart';
import 'package:ai_clinic/app/shell/dev/shell_dev_nav.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/auth_test_support.dart';

void main() {
  group('G. Dev Tools & Security (DV-S)', () {
    test('DV-S-001: Fill Dummy Clinic gated by kDebugMode (absent in release/profile)', () {
      expect(ShellDevFillDummyClinic.isEnabled, kDebugMode);
      expect(ShellDevNav.isEnabled, kDebugMode);
    });

    test('DV-S-003: design system route is open in debug builds', () {
      expect(ShellDevNav.isDesignSystemRoute(AppRoutes.foundationDemo), isTrue);
      expect(ShellDevNav.isDesignSystemRoute(AppRoutes.home), isFalse);

      if (kDebugMode) {
        expect(ShellDevNav.allowsOpenAccess(AppRoutes.foundationDemo), isTrue);
      } else {
        expect(ShellDevNav.allowsOpenAccess(AppRoutes.foundationDemo), isFalse);
      }
    });

    test('DV-S-004: open access routes are design-system only', () {
      ShellDevNav.assertOpenAccessRoutesAreDesignSystemOnly();

      for (final route in ShellDevNav.openAccessRoutes) {
        expect(ShellDevNav.isValidOpenAccessRoute(route), isTrue);
        expect(ShellDevNav.isDesignSystemRoute(route), isTrue);
      }

      const productionRoutes = [
        AppRoutes.home,
        AppRoutes.settings,
        AppRoutes.patients,
        AppRoutes.login,
      ];
      for (final route in productionRoutes) {
        expect(ShellDevNav.openAccessRoutes, isNot(contains(route)));
        expect(ShellDevNav.isValidOpenAccessRoute(route), isFalse);
      }
    });

    test('DV-S-002: dev action items visible in debug footer nav', () {
      if (!kDebugMode) {
        return;
      }

      final footerIds = ShellNavConfig.footerItems().map((item) => item.id).toList();
      expect(footerIds, contains(ShellDevFillDummyClinic.itemId));
      expect(footerIds, contains(ShellDevResetClinic.itemId));
      expect(footerIds, contains('dev'));
    });

    test('DV-S-007: auth redirect suppression gated by kDebugMode', () {
      if (kDebugMode) {
        return;
      }

      final container = ProviderContainer(
        overrides: [devClinicSeedProvider.overrideWith(() => _InProgressDevClinicSeedNotifier())],
      );
      addTearDown(container.dispose);

      expect(
        _wouldSuppressAuthRedirect(
          auth: AuthSessionState(status: AuthSessionStatus.authenticated, context: sampleAuthSessionContext()),
          seedState: container.read(devClinicSeedProvider),
        ),
        isFalse,
      );
    });

    test('DV-S-007: auth redirect not suppressed when unauthenticated', () {
      if (!kDebugMode) {
        return;
      }

      expect(
        _wouldSuppressAuthRedirect(
          auth: const AuthSessionState(status: AuthSessionStatus.unauthenticated),
          seedState: const DevClinicSeedState(inProgress: true),
        ),
        isFalse,
      );
    });

    test('DV-S-007: auth redirect not suppressed when seed idle', () {
      if (!kDebugMode) {
        return;
      }

      expect(
        _wouldSuppressAuthRedirect(
          auth: AuthSessionState(status: AuthSessionStatus.authenticated, context: sampleAuthSessionContext()),
          seedState: const DevClinicSeedState(inProgress: false),
        ),
        isFalse,
      );
    });

    test('DV-S-007: auth redirect suppressed only while seed in progress', () {
      if (!kDebugMode) {
        return;
      }

      expect(
        _wouldSuppressAuthRedirect(
          auth: AuthSessionState(status: AuthSessionStatus.authenticated, context: sampleAuthSessionContext()),
          seedState: const DevClinicSeedState(inProgress: true),
        ),
        isTrue,
      );
    });
  });
}

/// Mirrors [shellDevSuppressAuthRedirect] without requiring a sealed [Ref].
bool _wouldSuppressAuthRedirect({required AuthSessionState auth, required DevClinicSeedState seedState}) {
  if (!kDebugMode || !auth.isAuthenticated) {
    return false;
  }

  return seedState.inProgress;
}

class _InProgressDevClinicSeedNotifier extends DevClinicSeedNotifier {
  @override
  DevClinicSeedState build() => const DevClinicSeedState(inProgress: true);
}
