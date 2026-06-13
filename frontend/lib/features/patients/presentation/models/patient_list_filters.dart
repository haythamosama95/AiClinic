import 'package:flutter/foundation.dart';

import 'package:ai_clinic/features/patients/domain/patient_list_item.dart';
import 'package:ai_clinic/features/patients/presentation/utils/patient_presentation_formatting.dart';

/// Sort options for the patients list (server-backed via `search_patients`).
enum PatientSortField { nameAsc, nameDesc, lastVisitAsc, lastVisitDesc }

/// Last-visit date range filter (server-backed via `search_patients`).
enum PatientLastVisitFilter { any, last30Days, last90Days, over90Days, never }

extension PatientSortFieldWire on PatientSortField {
  String get wireValue => switch (this) {
    PatientSortField.nameAsc => 'name_asc',
    PatientSortField.nameDesc => 'name_desc',
    PatientSortField.lastVisitAsc => 'last_visit_asc',
    PatientSortField.lastVisitDesc => 'last_visit_desc',
  };
}

extension PatientLastVisitFilterWire on PatientLastVisitFilter {
  String get wireValue => switch (this) {
    PatientLastVisitFilter.any => 'any',
    PatientLastVisitFilter.last30Days => 'last_30_days',
    PatientLastVisitFilter.last90Days => 'last_90_days',
    PatientLastVisitFilter.over90Days => 'over_90_days',
    PatientLastVisitFilter.never => 'never',
  };
}

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

  String get displayId => PatientPresentationFormatting.displayId(item.id);

  DateTime? get lastVisitAt => item.lastVisitAt;

  DateTime? get nextAppointmentAt => item.nextAppointmentAt;

  int? get age => PatientPresentationFormatting.ageYears(item.dateOfBirth);

  String get ageGenderLabel => PatientPresentationFormatting.ageGenderLabel(age: age, gender: item.gender);

  static List<PatientTableRow> fromItems(List<PatientListItem> items) {
    return items.map((item) => PatientTableRow(item: item)).toList();
  }
}
