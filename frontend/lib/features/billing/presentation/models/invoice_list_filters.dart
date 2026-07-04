import 'package:flutter/foundation.dart';

/// Filters for the invoice list page (`list_invoices`, V1-6 US5).
@immutable
class InvoiceListFilters {
  const InvoiceListFilters({
    this.statuses = const [],
    this.patientSearch = '',
    this.invoiceNumber = '',
    this.branchId,
    this.dateFrom,
    this.dateTo,
    this.page = 1,
    this.pageSize = 50,
  });

  final List<String> statuses;
  final String patientSearch;
  final String invoiceNumber;
  final String? branchId;
  final DateTime? dateFrom;
  final DateTime? dateTo;
  final int page;
  final int pageSize;

  int get offset => (page - 1) * pageSize;

  bool get hasActiveFilters =>
      statuses.isNotEmpty ||
      patientSearch.trim().isNotEmpty ||
      invoiceNumber.trim().isNotEmpty ||
      branchId != null ||
      dateFrom != null ||
      dateTo != null;

  InvoiceListFilters copyWith({
    List<String>? statuses,
    String? patientSearch,
    String? invoiceNumber,
    String? branchId,
    bool clearBranchId = false,
    DateTime? dateFrom,
    bool clearDateFrom = false,
    DateTime? dateTo,
    bool clearDateTo = false,
    int? page,
    int? pageSize,
  }) {
    return InvoiceListFilters(
      statuses: statuses ?? this.statuses,
      patientSearch: patientSearch ?? this.patientSearch,
      invoiceNumber: invoiceNumber ?? this.invoiceNumber,
      branchId: clearBranchId ? null : (branchId ?? this.branchId),
      dateFrom: clearDateFrom ? null : (dateFrom ?? this.dateFrom),
      dateTo: clearDateTo ? null : (dateTo ?? this.dateTo),
      page: page ?? this.page,
      pageSize: pageSize ?? this.pageSize,
    );
  }

  Map<String, dynamic> toRpcFilters({List<String>? branchIds}) {
    final filters = <String, dynamic>{};
    if (branchIds != null && branchIds.isNotEmpty) {
      filters['branch_ids'] = branchIds;
    }
    if (branchId != null && branchId!.isNotEmpty) {
      filters['branch_ids'] = [branchId];
    }
    if (statuses.isNotEmpty) {
      filters['statuses'] = statuses;
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
      filters['date_to'] = dateTo!.toUtc().toIso8601String();
    }
    return filters;
  }
}
