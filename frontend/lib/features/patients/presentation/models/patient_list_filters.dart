import 'package:flutter/foundation.dart';

import 'package:ai_clinic/features/patients/domain/patient_last_visit_filter.dart';
import 'package:ai_clinic/features/patients/domain/patient_list_item.dart';
import 'package:ai_clinic/features/patients/domain/patient_sort_field.dart';

/// Filter and pagination state for the patients list view.
@immutable
class PatientListFilters {
  /// Sentinel [branchId] for organization-wide patient search (all branches).
  static const allBranchesSentinel = '__all_branches__';

  const PatientListFilters({
    this.searchText = '',
    this.branchId,
    this.lastVisitFilter = PatientLastVisitFilter.any,
    this.sortField = PatientSortField.nameAsc,
    this.page = 1,
    this.pageSize = 20,
  });

  final String searchText;
  final String? branchId;
  final PatientLastVisitFilter lastVisitFilter;
  final PatientSortField sortField;
  final int page;
  final int pageSize;

  bool get isAllBranchesFilter => branchId == allBranchesSentinel;

  int get offset => (page - 1) * pageSize;

  bool get hasActiveFilters =>
      (branchId != null && branchId!.isNotEmpty) || lastVisitFilter != PatientLastVisitFilter.any;

  bool get hasSearchOrFilters => searchText.trim().isNotEmpty || hasActiveFilters;

  int get activeFilterCount {
    var count = 0;
    if (branchId != null && branchId!.isNotEmpty) {
      count++;
    }
    if (lastVisitFilter != PatientLastVisitFilter.any) {
      count++;
    }
    return count;
  }

  PatientListFilters copyWith({
    String? searchText,
    Object? branchId = _sentinel,
    PatientLastVisitFilter? lastVisitFilter,
    PatientSortField? sortField,
    int? page,
    int? pageSize,
  }) {
    return PatientListFilters(
      searchText: searchText ?? this.searchText,
      branchId: identical(branchId, _sentinel) ? this.branchId : branchId as String?,
      lastVisitFilter: lastVisitFilter ?? this.lastVisitFilter,
      sortField: sortField ?? this.sortField,
      page: page ?? this.page,
      pageSize: pageSize ?? this.pageSize,
    );
  }

  static const _sentinel = Object();
}

/// Presentation row combining list data with optional visit/appointment metadata.
@immutable
class PatientTableRow {
  const PatientTableRow({required this.item});

  final PatientListItem item;

  static List<PatientTableRow> fromItems(List<PatientListItem> items) {
    return items.map((item) => PatientTableRow(item: item)).toList();
  }
}
