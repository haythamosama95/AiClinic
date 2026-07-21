import 'package:flutter/foundation.dart';

import 'package:ai_clinic/core/ui/components/app_list_control_bar.dart';
import 'package:ai_clinic/features/billing/domain/invoice_status.dart';
import 'package:ai_clinic/features/billing/presentation/models/invoice_list_filters.dart';
import 'package:ai_clinic/features/billing/presentation/models/invoice_sort_key.dart';

/// Page-local filter/sort state for the invoice list (web `InvoiceListControls`).
@immutable
class InvoiceListControls {
  const InvoiceListControls({
    this.search = '',
    this.status,
    this.branch,
    this.sort = InvoiceSortKey.dateDesc,
    this.page = 1,
    this.pageSize = 10,
  });

  final String search;
  final InvoiceStatus? status;
  final String? branch;
  final InvoiceSortKey sort;
  final int page;
  final int pageSize;

  static const defaultControls = InvoiceListControls();
  static const initial = defaultControls;

  bool get sortIsCustom => sort != InvoiceSortKey.dateDesc;

  bool get isFiltered => search.trim().isNotEmpty || status != null || branch != null || sortIsCustom;

  /// Reconstructs page controls from backbone [InvoiceListFilters] (notifier source of truth).
  factory InvoiceListControls.fromBackendFilters(InvoiceListFilters filters) {
    final statuses = filters.statuses;
    return InvoiceListControls(
      search: filters.patientSearch,
      status: statuses.isEmpty ? null : InvoiceStatus.tryParse(statuses.first),
      branch: filters.branchId,
      sort: InvoiceSortKey.fromFilters(filters),
      page: filters.page,
      pageSize: filters.pageSize,
    );
  }

  int get filterActiveCount => (status != null ? 1 : 0) + (branch != null ? 1 : 0);

  InvoiceListControls copyWith({
    String? search,
    InvoiceStatus? status,
    bool clearStatus = false,
    String? branch,
    bool clearBranch = false,
    InvoiceSortKey? sort,
    int? page,
    int? pageSize,
  }) {
    return InvoiceListControls(
      search: search ?? this.search,
      status: clearStatus ? null : (status ?? this.status),
      branch: clearBranch ? null : (branch ?? this.branch),
      sort: sort ?? this.sort,
      page: page ?? this.page,
      pageSize: pageSize ?? this.pageSize,
    );
  }

  InvoiceListFilters toBackendFilters({required bool multiBranch}) {
    final (sortField, sortDirection) = sort.backendSort;
    final trimmedSearch = search.trim();
    return InvoiceListFilters(
      patientSearch: trimmedSearch,
      statuses: status != null ? [status!.wireValue] : const [],
      branchId: multiBranch ? branch : null,
      sortField: sortField,
      sortDirection: sortDirection,
      page: page,
      pageSize: pageSize,
    );
  }

  List<AppActiveFilter> activeFilters({
    required bool multiBranch,
    required String Function(String branchId) branchName,
    required VoidCallback onRemoveStatus,
    required VoidCallback onRemoveBranch,
    required VoidCallback onRemoveSearch,
  }) {
    final chips = <AppActiveFilter>[];

    final currentStatus = status;
    if (currentStatus != null) {
      chips.add(AppActiveFilter(id: 'status', label: currentStatus.label, onRemove: onRemoveStatus));
    }

    final currentBranch = branch;
    if (multiBranch && currentBranch != null) {
      chips.add(AppActiveFilter(id: 'branch', label: branchName(currentBranch), onRemove: onRemoveBranch));
    }

    final query = search.trim();
    if (query.isNotEmpty) {
      chips.add(AppActiveFilter(id: 'search', label: 'Search: $query', onRemove: onRemoveSearch));
    }

    return chips;
  }

  @override
  bool operator ==(Object other) {
    return other is InvoiceListControls &&
        other.search == search &&
        other.status == status &&
        other.branch == branch &&
        other.sort == sort &&
        other.page == page &&
        other.pageSize == pageSize;
  }

  @override
  int get hashCode => Object.hash(search, status, branch, sort, page, pageSize);
}
