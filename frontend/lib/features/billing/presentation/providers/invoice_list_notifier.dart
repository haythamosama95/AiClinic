import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/features/billing/data/invoice_repository.dart';
import 'package:ai_clinic/features/billing/domain/invoice_list_item.dart';
import 'package:ai_clinic/features/billing/presentation/models/invoice_list_controls.dart';
import 'package:ai_clinic/features/billing/presentation/models/invoice_list_filters.dart';
import 'package:ai_clinic/features/billing/presentation/models/invoice_sort_key.dart';

@immutable
class InvoiceListUiState {
  const InvoiceListUiState({
    required this.items,
    required this.hasMore,
    required this.filters,
    required this.estimatedTotal,
    required this.hasInvoices,
  });

  final List<InvoiceListItem> items;
  final bool hasMore;
  final InvoiceListFilters filters;

  /// Best-effort count for pagination footer (offset + loaded + hasMore hint).
  final int estimatedTotal;

  /// True when the branch has at least one invoice (unfiltered probe).
  final bool hasInvoices;

  bool get isEmpty => items.isEmpty;

  bool get isNoInvoicesYet => isEmpty && !hasInvoices;

  bool get isNoMatch => isEmpty && hasInvoices;
}

/// Paginated invoice list with debounced filters (V1-6 US5).
final invoiceListProvider =
    AsyncNotifierProvider<InvoiceListNotifier, InvoiceListUiState>(
      InvoiceListNotifier.new,
    );

class InvoiceListNotifier extends AsyncNotifier<InvoiceListUiState> {
  InvoiceListFilters _filters = const InvoiceListFilters();
  var _hasInvoices = false;

  InvoiceListFilters get filters => _filters;

  @override
  Future<InvoiceListUiState> build() async {
    ref.watch(
      authSessionProvider.select((state) => state.context?.activeBranchId),
    );
    return _load(_filters);
  }

  Future<void> applyFilters(InvoiceListFilters filters) async {
    _filters = filters;
    // Reflect filter changes immediately so list controls and open filter
    // popovers rebuild while the next page is loading.
    final previous = state.value;
    if (previous != null) {
      state = AsyncData(
        InvoiceListUiState(
          items: previous.items,
          hasMore: previous.hasMore,
          filters: filters,
          estimatedTotal: previous.estimatedTotal,
          hasInvoices: previous.hasInvoices,
        ),
      );
    }
    state = await AsyncValue.guard(() => _load(filters));
  }

  Future<void> applyControls(
    InvoiceListControls controls, {
    required bool multiBranch,
  }) async {
    await applyFilters(controls.toBackendFilters(multiBranch: multiBranch));
  }

  Future<void> reload() async {
    state = await AsyncValue.guard(() => _load(_filters));
  }

  bool _isPristineProbe(InvoiceListFilters filters) {
    return filters.statuses.isEmpty &&
        filters.patientSearch.trim().isEmpty &&
        filters.invoiceNumber.trim().isEmpty &&
        filters.branchId == null &&
        filters.dateFrom == null &&
        filters.dateTo == null &&
        filters.page == 1;
  }

  Future<InvoiceListUiState> _load(InvoiceListFilters filters) async {
    final auth = ref.read(authSessionProvider);
    if (!AuthRouteGuard.canAccessInvoiceList(auth)) {
      return InvoiceListUiState(
        items: const [],
        hasMore: false,
        filters: filters,
        estimatedTotal: 0,
        hasInvoices: false,
      );
    }

    final branchIds = auth.context?.branchIds ?? const <String>[];
    final page = await ref
        .read(invoiceRepositoryProvider)
        .listInvoices(
          filters: filters.toRpcFilters(branchIds: branchIds),
          limit: filters.pageSize,
          offset: filters.offset,
        );

    if (_isPristineProbe(filters)) {
      _hasInvoices = page.items.isNotEmpty || page.hasMore;
    }

    // Backend currently ignores sort_field/sort_direction; sort the loaded page client-side.
    final items = sortInvoiceListItemsClientSide(page.items, filters);

    final estimatedTotal =
        filters.offset + items.length + (page.hasMore ? 1 : 0);

    return InvoiceListUiState(
      items: items,
      hasMore: page.hasMore,
      filters: filters,
      estimatedTotal: estimatedTotal,
      hasInvoices: _hasInvoices,
    );
  }
}
