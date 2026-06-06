import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/billing/data/invoice_repository.dart';
import 'package:ai_clinic/features/billing/domain/invoice_list_item.dart';
import 'package:ai_clinic/features/billing/presentation/billing_rpc_messages.dart';

@immutable
class PatientInvoiceHistoryState {
  const PatientInvoiceHistoryState({
    this.items = const [],
    this.loading = false,
    this.isLoadingMore = false,
    this.error,
    this.loadMoreError,
    this.offset = 0,
    this.pageSize = 20,
    this.hasMore = false,
  });

  final List<InvoiceListItem> items;
  final bool loading;
  final bool isLoadingMore;
  final String? error;
  final String? loadMoreError;
  final int offset;
  final int pageSize;
  final bool hasMore;

  PatientInvoiceHistoryState copyWith({
    List<InvoiceListItem>? items,
    bool? loading,
    bool? isLoadingMore,
    Object? error = _sentinel,
    Object? loadMoreError = _sentinel,
    int? offset,
    bool? hasMore,
    bool clearError = false,
    bool clearLoadMoreError = false,
  }) {
    return PatientInvoiceHistoryState(
      items: items ?? this.items,
      loading: loading ?? this.loading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      error: clearError ? null : (identical(error, _sentinel) ? this.error : error as String?),
      loadMoreError: clearLoadMoreError
          ? null
          : (identical(loadMoreError, _sentinel) ? this.loadMoreError : loadMoreError as String?),
      offset: offset ?? this.offset,
      pageSize: pageSize,
      hasMore: hasMore ?? this.hasMore,
    );
  }
}

const _sentinel = Object();

final patientInvoiceHistoryProvider = NotifierProvider.autoDispose
    .family<PatientInvoiceHistoryNotifier, PatientInvoiceHistoryState, String>(PatientInvoiceHistoryNotifier.new);

class PatientInvoiceHistoryNotifier extends Notifier<PatientInvoiceHistoryState> {
  PatientInvoiceHistoryNotifier(this._patientId);

  final String _patientId;

  @override
  PatientInvoiceHistoryState build() {
    Future.microtask(reload);
    return const PatientInvoiceHistoryState(loading: true);
  }

  Future<void> reload() async {
    state = state.copyWith(loading: true, clearError: true, clearLoadMoreError: true);

    try {
      final page = await _fetch(offset: 0);
      state = state.copyWith(items: page.items, loading: false, offset: 0, hasMore: page.hasMore);
    } catch (error) {
      state = state.copyWith(loading: false, items: const [], error: error.toString());
    }
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

  Future<InvoiceListPageResult> _fetch({required int offset}) async {
    try {
      return await ref
          .read(invoiceRepositoryProvider)
          .listPatientInvoices(patientId: _patientId, limit: state.pageSize, offset: offset);
    } on RpcFailure catch (failure) {
      throw StateError(billingMessageForRpc(failure));
    }
  }
}
