import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/features/billing/data/insurance_provider_repository.dart';
import 'package:ai_clinic/features/billing/domain/insurance_provider.dart';

/// Insurance provider catalog for editor and management screens (V1-6 US4).
final insuranceProvidersProvider = AsyncNotifierProvider<InsuranceProvidersNotifier, List<InsuranceProvider>>(
  InsuranceProvidersNotifier.new,
);

class InsuranceProvidersNotifier extends AsyncNotifier<List<InsuranceProvider>> {
  @override
  Future<List<InsuranceProvider>> build() async {
    final auth = ref.watch(authSessionProvider);
    if (!AuthRouteGuard.canAccessInsuranceProviders(auth)) {
      return const [];
    }

    return ref.read(insuranceProviderRepositoryProvider).listProviders(onlyActive: false);
  }

  Future<void> reload() async {
    state = await AsyncValue.guard(
      () => ref.read(insuranceProviderRepositoryProvider).listProviders(onlyActive: false),
    );
  }

  Future<String> upsert({String? id, required String name, String? contactInfo, bool isActive = true}) async {
    final providerId = await ref
        .read(insuranceProviderRepositoryProvider)
        .upsertProvider(id: id, name: name, contactInfo: contactInfo, isActive: isActive);
    await reload();
    return providerId;
  }

  Future<void> deactivate(String providerId) async {
    await ref.read(insuranceProviderRepositoryProvider).deactivateProvider(providerId: providerId);
    await reload();
  }
}

/// Active providers only — for invoice editor insurance selector.
final activeInsuranceProvidersProvider = FutureProvider.autoDispose<List<InsuranceProvider>>((ref) async {
  return ref.read(insuranceProviderRepositoryProvider).listProviders(onlyActive: true);
});
