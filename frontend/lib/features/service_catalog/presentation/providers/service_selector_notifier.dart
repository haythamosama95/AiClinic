import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/features/service_catalog/data/service_catalog_repository.dart';
import 'package:ai_clinic/features/service_catalog/domain/eligible_service.dart';

/// Debounced eligible-service search for the invoice editor (Service Catalog 015 US2).
final serviceSelectorProvider = AsyncNotifierProvider.autoDispose
    .family<ServiceSelectorNotifier, List<EligibleService>, String>(ServiceSelectorNotifier.new);

class ServiceSelectorNotifier extends AsyncNotifier<List<EligibleService>> {
  ServiceSelectorNotifier(this._branchId);

  final String _branchId;
  Timer? _debounce;
  String _lastQuery = '';

  @override
  Future<List<EligibleService>> build() async {
    ref.onDispose(() => _debounce?.cancel());
    return const [];
  }

  ServiceCatalogRepository get _repo => ref.read(serviceCatalogRepositoryProvider);

  void search(String query, {Duration debounce = const Duration(milliseconds: 300)}) {
    _debounce?.cancel();
    _debounce = Timer(debounce, () {
      unawaited(_runSearch(query));
    });
  }

  Future<void> _runSearch(String query) async {
    _lastQuery = query;
    state = const AsyncLoading();

    try {
      final results = await _repo.searchEligibleServices(branchId: _branchId, query: query);
      if (_lastQuery != query) {
        return;
      }
      state = AsyncData(results);
    } catch (error, stackTrace) {
      if (_lastQuery != query) {
        return;
      }
      state = AsyncError<List<EligibleService>>(error, stackTrace);
    }
  }
}
