import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/features/billing/data/invoice_repository.dart';
import 'package:ai_clinic/features/billing/domain/invoice_list_item.dart';
import 'package:ai_clinic/features/billing/presentation/models/invoice_list_filters.dart';

@immutable
class InvoiceListUiState {
  const InvoiceListUiState({
    required this.items,
    required this.hasMore,
    required this.filters,
    required this.estimatedTotal,
  });

  final List<InvoiceListItem> items;
  final bool hasMore;
  final InvoiceListFilters filters;

  /// Best-effort count for pagination footer (offset + loaded + hasMore hint).
  final int estimatedTotal;

  bool get isEmpty => items.isEmpty;
}

/// Paginated invoice list with debounced filters (V1-6 US5).
final invoiceListProvider = AsyncNotifierProvider<InvoiceListNotifier, InvoiceListUiState>(InvoiceListNotifier.new);

class InvoiceListNotifier extends AsyncNotifier<InvoiceListUiState> {
  InvoiceListFilters _filters = const InvoiceListFilters();

  InvoiceListFilters get filters => _filters;

  @override
  Future<InvoiceListUiState> build() async {
    ref.watch(authSessionProvider.select((state) => state.context?.activeBranchId));
    return _load(_filters);
  }

  Future<void> applyFilters(InvoiceListFilters filters) async {
    _filters = filters;
    state = await AsyncValue.guard(() => _load(filters));
  }

  Future<void> reload() async {
    state = await AsyncValue.guard(() => _load(_filters));
  }

  Future<InvoiceListUiState> _load(InvoiceListFilters filters) async {
    final auth = ref.read(authSessionProvider);
    if (!AuthRouteGuard.canAccessInvoiceList(auth)) {
      return InvoiceListUiState(items: const [], hasMore: false, filters: filters, estimatedTotal: 0);
    }

    final branchIds = auth.context?.branchIds ?? const <String>[];
    final page = await ref
        .read(invoiceRepositoryProvider)
        .listInvoices(
          filters: filters.toRpcFilters(branchIds: branchIds),
          limit: filters.pageSize,
          offset: filters.offset,
        );

    final estimatedTotal = filters.offset + page.items.length + (page.hasMore ? 1 : 0);

    return InvoiceListUiState(
      items: page.items,
      hasMore: page.hasMore,
      filters: filters,
      estimatedTotal: estimatedTotal,
    );
  }
}
