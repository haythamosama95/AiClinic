import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/features/service_catalog/data/service_catalog_repository.dart';
import 'package:ai_clinic/features/service_catalog/domain/service_list_item.dart';
import 'package:ai_clinic/features/service_catalog/presentation/models/service_list_filters.dart';

@immutable
class ServiceCatalogListUiState {
  const ServiceCatalogListUiState({required this.items, required this.total, required this.filters});

  final List<ServiceListItem> items;
  final int total;
  final ServiceListFilters filters;

  bool get isEmpty => items.isEmpty;
  bool get hasMore => filters.offset + items.length < total;
}

/// Backend-first paginated service catalog list (015 US6).
final serviceCatalogListProvider = AsyncNotifierProvider<ServiceCatalogListNotifier, ServiceCatalogListUiState>(
  ServiceCatalogListNotifier.new,
);

class ServiceCatalogListNotifier extends AsyncNotifier<ServiceCatalogListUiState> {
  ServiceListFilters _filters = const ServiceListFilters();

  ServiceListFilters get filters => _filters;

  @override
  Future<ServiceCatalogListUiState> build() async {
    return _load(_filters);
  }

  Future<void> applyFilters(ServiceListFilters filters) async {
    _filters = filters;
    state = await AsyncValue.guard(() => _load(filters));
  }

  Future<void> reload() async {
    state = await AsyncValue.guard(() => _load(_filters));
  }

  Future<ServiceCatalogListUiState> _load(ServiceListFilters filters) async {
    final auth = ref.read(authSessionProvider);
    if (!AuthRouteGuard.canAccessServiceCatalogList(auth)) {
      return ServiceCatalogListUiState(items: const [], total: 0, filters: filters);
    }

    final page = await ref
        .read(serviceCatalogRepositoryProvider)
        .listServices(
          query: filters.query,
          globalStatus: filters.globalStatus,
          branchId: filters.branchId,
          limit: filters.pageSize,
          offset: filters.offset,
        );

    return ServiceCatalogListUiState(items: page.items, total: page.total, filters: filters);
  }
}
