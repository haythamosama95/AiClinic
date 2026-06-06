import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/billing/data/insurance_provider_repository.dart';
import 'package:ai_clinic/features/billing/domain/insurance_provider.dart';
import 'package:ai_clinic/features/billing/presentation/billing_rpc_messages.dart';

@immutable
class InsuranceProvidersUiState {
  const InsuranceProvidersUiState({
    required this.providers,
    this.busyProviderId,
    this.errorMessage,
    this.successMessage,
  });

  final List<InsuranceProvider> providers;
  final String? busyProviderId;
  final String? errorMessage;
  final String? successMessage;

  bool get isBusy => busyProviderId != null;

  InsuranceProvidersUiState copyWith({
    List<InsuranceProvider>? providers,
    String? busyProviderId,
    String? errorMessage,
    String? successMessage,
    bool clearBusy = false,
    bool clearMessages = false,
  }) {
    return InsuranceProvidersUiState(
      providers: providers ?? this.providers,
      busyProviderId: clearBusy ? null : (busyProviderId ?? this.busyProviderId),
      errorMessage: clearMessages ? null : (errorMessage ?? this.errorMessage),
      successMessage: clearMessages ? null : (successMessage ?? this.successMessage),
    );
  }
}

final insuranceProvidersProvider = AsyncNotifierProvider<InsuranceProvidersNotifier, InsuranceProvidersUiState>(
  InsuranceProvidersNotifier.new,
);

class InsuranceProvidersNotifier extends AsyncNotifier<InsuranceProvidersUiState> {
  @override
  Future<InsuranceProvidersUiState> build() async {
    return _load();
  }

  Future<void> reload() async {
    state = const AsyncLoading();
    state = AsyncData(await _load());
  }

  Future<bool> upsertProvider({String? id, required String name, String? contactInfo}) async {
    final current = state.value;
    if (current == null) {
      return false;
    }

    state = AsyncData(current.copyWith(clearMessages: true));

    try {
      await ref
          .read(insuranceProviderRepositoryProvider)
          .upsertProvider(id: id, name: name, contactInfo: contactInfo, isActive: true);
      state = AsyncData((await _load()).copyWith(successMessage: 'Insurance provider saved.'));
      return true;
    } on RpcFailure catch (error) {
      state = AsyncData(current.copyWith(errorMessage: billingMessageForRpc(error)));
      return false;
    } catch (error) {
      state = AsyncData(current.copyWith(errorMessage: error.toString()));
      return false;
    }
  }

  Future<bool> deactivateProvider(String providerId) async {
    final current = state.value;
    if (current == null) {
      return false;
    }

    state = AsyncData(current.copyWith(busyProviderId: providerId, clearMessages: true));

    try {
      await ref.read(insuranceProviderRepositoryProvider).deactivateProvider(providerId: providerId);
      state = AsyncData((await _load()).copyWith(successMessage: 'Insurance provider deactivated.'));
      return true;
    } on RpcFailure catch (error) {
      state = AsyncData(current.copyWith(clearBusy: true, errorMessage: billingMessageForRpc(error)));
      return false;
    } catch (error) {
      state = AsyncData(current.copyWith(clearBusy: true, errorMessage: error.toString()));
      return false;
    }
  }

  void clearMessages() {
    final current = state.value;
    if (current == null) {
      return;
    }
    state = AsyncData(current.copyWith(clearMessages: true));
  }

  Future<InsuranceProvidersUiState> _load() async {
    final providers = await ref.read(insuranceProviderRepositoryProvider).listProviders(onlyActive: false);
    return InsuranceProvidersUiState(providers: providers);
  }
}

final activeInsuranceProvidersProvider = FutureProvider.autoDispose<List<InsuranceProvider>>((ref) {
  return ref.read(insuranceProviderRepositoryProvider).listProviders(onlyActive: true);
});
