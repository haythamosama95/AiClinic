import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/features/billing/data/billing_settings_repository.dart';
import 'package:ai_clinic/features/billing/domain/billing_settings.dart';

/// Organization billing settings with backend-first load (V1-6 US8).
final billingSettingsProvider = AsyncNotifierProvider<BillingSettingsNotifier, BillingSettings>(
  BillingSettingsNotifier.new,
);

class BillingSettingsNotifier extends AsyncNotifier<BillingSettings> {
  @override
  Future<BillingSettings> build() async {
    final auth = ref.watch(authSessionProvider);
    if (!AuthRouteGuard.canAccessBillingSettings(auth)) {
      return const BillingSettings(allowPartialPayments: false);
    }

    return ref.read(billingSettingsRepositoryProvider).get();
  }

  Future<void> reload() async {
    state = await AsyncValue.guard(() => ref.read(billingSettingsRepositoryProvider).get());
  }

  Future<void> updateAllowPartialPayments(bool value) async {
    final previous = state.value;
    state = AsyncData(BillingSettings(allowPartialPayments: value));
    state = await AsyncValue.guard(() async {
      await ref.read(billingSettingsRepositoryProvider).update(allowPartialPayments: value);
      return ref.read(billingSettingsRepositoryProvider).get();
    });
    if (state.hasError && previous != null) {
      state = AsyncData(previous);
    }
  }
}
