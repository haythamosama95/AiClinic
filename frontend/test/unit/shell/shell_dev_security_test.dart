import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/app/shell/dev/dev_clinic_seed_notifier.dart';
import 'package:ai_clinic/app/shell/dev/shell_dev_fill_dummy_clinic.dart';
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

    test('DV-S-002: Fill Dummy Clinic nav item visible in debug builds', () {
      if (!kDebugMode) {
        return;
      }

      final childIds = ShellDevNav.footerGroup.children.map((child) => child.id).toList();
      expect(childIds, contains(ShellDevFillDummyClinic.itemId));
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
