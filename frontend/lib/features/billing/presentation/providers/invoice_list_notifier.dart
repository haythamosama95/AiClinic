import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/billing/data/invoice_repository.dart';
import 'package:ai_clinic/features/billing/domain/invoice_list_item.dart';
import 'package:ai_clinic/features/billing/domain/invoice_status.dart';
import 'package:ai_clinic/features/billing/presentation/billing_rpc_messages.dart';

@immutable
class InvoiceListFilters {
  const InvoiceListFilters({
    this.status,
    this.branchId,
    this.patientSearch = '',
    this.invoiceNumber = '',
    this.dateFrom,
    this.dateTo,
  });

  final InvoiceStatus? status;
  final String? branchId;
  final String patientSearch;
  final String invoiceNumber;
  final DateTime? dateFrom;
  final DateTime? dateTo;

  Map<String, dynamic> toRpcFilters() {
    final filters = <String, dynamic>{};
    if (status != null) {
      filters['statuses'] = [status!.wireValue];
    }
    final branchId = this.branchId?.trim();
    if (branchId != null && branchId.isNotEmpty) {
      filters['branch_ids'] = [branchId];
    }
    final search = patientSearch.trim();
    if (search.isNotEmpty) {
      filters['patient_search'] = search;
    }
    final number = invoiceNumber.trim();
    if (number.isNotEmpty) {
      filters['invoice_number'] = number;
    }
    if (dateFrom != null) {
      filters['date_from'] = dateFrom!.toUtc().toIso8601String();
    }
    if (dateTo != null) {
      filters['date_to'] = DateTime.utc(dateTo!.year, dateTo!.month, dateTo!.day, 23, 59, 59).toIso8601String();
    }
    return filters;
  }

  InvoiceListFilters copyWith({
    Object? status = _sentinel,
    Object? branchId = _sentinel,
    String? patientSearch,
    String? invoiceNumber,
    Object? dateFrom = _sentinel,
    Object? dateTo = _sentinel,
    bool clearStatus = false,
    bool clearBranchId = false,
    bool clearDateRange = false,
  }) {
    return InvoiceListFilters(
      status: clearStatus ? null : (identical(status, _sentinel) ? this.status : status as InvoiceStatus?),
      branchId: clearBranchId ? null : (identical(branchId, _sentinel) ? this.branchId : branchId as String?),
      patientSearch: patientSearch ?? this.patientSearch,
      invoiceNumber: invoiceNumber ?? this.invoiceNumber,
      dateFrom: clearDateRange ? null : (identical(dateFrom, _sentinel) ? this.dateFrom : dateFrom as DateTime?),
      dateTo: clearDateRange ? null : (identical(dateTo, _sentinel) ? this.dateTo : dateTo as DateTime?),
    );
  }
}

@immutable
class InvoiceListUiState {
  const InvoiceListUiState({
    this.items = const [],
    this.loading = false,
    this.isLoadingMore = false,
    this.error,
    this.loadMoreError,
    this.filters = const InvoiceListFilters(),
    this.offset = 0,
    this.pageSize = 25,
    this.hasMore = false,
  });

  final List<InvoiceListItem> items;
  final bool loading;
  final bool isLoadingMore;
  final String? error;
  final String? loadMoreError;
  final InvoiceListFilters filters;
  final int offset;
  final int pageSize;
  final bool hasMore;

  InvoiceListUiState copyWith({
    List<InvoiceListItem>? items,
    bool? loading,
    bool? isLoadingMore,
    Object? error = _sentinel,
    Object? loadMoreError = _sentinel,
    InvoiceListFilters? filters,
    int? offset,
    int? pageSize,
    bool? hasMore,
    bool clearError = false,
    bool clearLoadMoreError = false,
  }) {
    return InvoiceListUiState(
      items: items ?? this.items,
      loading: loading ?? this.loading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      error: clearError ? null : (identical(error, _sentinel) ? this.error : error as String?),
      loadMoreError: clearLoadMoreError
          ? null
          : (identical(loadMoreError, _sentinel) ? this.loadMoreError : loadMoreError as String?),
      filters: filters ?? this.filters,
      offset: offset ?? this.offset,
      pageSize: pageSize ?? this.pageSize,
      hasMore: hasMore ?? this.hasMore,
    );
  }
}

const _sentinel = Object();

class InvoiceListNotifier extends Notifier<InvoiceListUiState> {
  Timer? _debounceTimer;
  int _reloadGeneration = 0;

  static const _debounceDelay = Duration(milliseconds: 500);

  @override
  InvoiceListUiState build() {
    ref.onDispose(() => _debounceTimer?.cancel());
    ref.listen<AuthSessionState>(authSessionProvider, (previous, next) {
      if (previous?.context?.activeBranchId != next.context?.activeBranchId) {
        unawaited(reload());
      }
    });

    Future.microtask(reload);
    return const InvoiceListUiState(loading: true);
  }

  Future<void> reload({InvoiceListFilters? filters}) async {
    _debounceTimer?.cancel();
    final nextFilters = filters ?? state.filters;
    final generation = ++_reloadGeneration;

    state = state.copyWith(loading: true, filters: nextFilters, clearError: true, clearLoadMoreError: true);

    try {
      final page = await _fetch(offset: 0);
      if (generation != _reloadGeneration) {
        return;
      }

      state = state.copyWith(items: page.items, loading: false, offset: 0, hasMore: page.hasMore, clearError: true);
    } catch (error) {
      if (generation != _reloadGeneration) {
        return;
      }
      state = state.copyWith(loading: false, items: const [], error: error.toString());
    }
  }

  void setStatusFilter(InvoiceStatus? status) {
    unawaited(
      reload(
        filters: state.filters.copyWith(status: status, clearStatus: status == null),
      ),
    );
  }

  void setBranchFilter(String? branchId) {
    unawaited(
      reload(
        filters: state.filters.copyWith(branchId: branchId, clearBranchId: branchId == null),
      ),
    );
  }

  void setInvoiceNumberFilter(String value) {
    _scheduleDebouncedReload(state.filters.copyWith(invoiceNumber: value));
  }

  void setPatientSearch(String value) {
    _scheduleDebouncedReload(state.filters.copyWith(patientSearch: value));
  }

  void setDateRange({DateTime? from, DateTime? to}) {
    unawaited(
      reload(
        filters: state.filters.copyWith(dateFrom: from, dateTo: to, clearDateRange: from == null && to == null),
      ),
    );
  }

  Future<void> loadMore() async {
    if (state.loading || state.isLoadingMore || !state.hasMore) {
      return;
    }

    state = state.copyWith(isLoadingMore: true, clearLoadMoreError: true);
    final nextOffset = state.offset + state.pageSize;

    try {
      final page = await _fetch(offset: nextOffset);
      state = state.copyWith(
        items: [...state.items, ...page.items],
        offset: nextOffset,
        isLoadingMore: false,
        hasMore: page.hasMore,
      );
    } catch (error) {
      state = state.copyWith(isLoadingMore: false, loadMoreError: error.toString());
    }
  }

  void _scheduleDebouncedReload(InvoiceListFilters filters) {
    state = state.copyWith(filters: filters);
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceDelay, () {
      unawaited(reload());
    });
  }

  Future<InvoiceListPageResult> _fetch({required int offset}) async {
    try {
      return await ref
          .read(invoiceRepositoryProvider)
          .listInvoices(filters: state.filters.toRpcFilters(), limit: state.pageSize, offset: offset);
    } on RpcFailure catch (failure) {
      throw StateError(billingMessageForRpc(failure));
    }
  }
}

final invoiceListProvider = NotifierProvider<InvoiceListNotifier, InvoiceListUiState>(InvoiceListNotifier.new);
