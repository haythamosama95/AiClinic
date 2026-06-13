import 'package:flutter/foundation.dart';

import 'package:ai_clinic/features/patients/domain/patient_list_item.dart';
import 'package:ai_clinic/features/patients/domain/patient_search_query.dart';
import 'package:ai_clinic/features/patients/presentation/utils/patient_presentation_formatting.dart';

/// Sort options for the patients list (client-side until RPC supports ordering).
enum PatientSortField { nameAsc, nameDesc, lastVisitAsc, lastVisitDesc }

/// Last-visit date range filter (client-side placeholder until visit data is joined).
enum PatientLastVisitFilter { any, last30Days, last90Days, over90Days, never }

/// Filter and pagination state for the patients list view.
@immutable
class PatientListFilters {
  /// Sentinel [branchId] for organization-wide patient search (all branches).
  static const allBranchesSentinel = '__all_branches__';

  const PatientListFilters({
    this.searchText = '',
    this.branchId,
    this.assignedDoctorId,
    this.lastVisitFilter = PatientLastVisitFilter.any,
    this.sortField = PatientSortField.nameAsc,
    this.page = 1,
    this.pageSize = 20,
  });

  final String searchText;
  final String? branchId;
  final String? assignedDoctorId;
  final PatientLastVisitFilter lastVisitFilter;
  final PatientSortField sortField;
  final int page;
  final int pageSize;

  bool get isAllBranchesFilter => branchId == allBranchesSentinel;

  int get offset => (page - 1) * pageSize;

  bool get hasActiveFilters =>
      (branchId != null && branchId!.isNotEmpty) ||
      (assignedDoctorId != null && assignedDoctorId!.isNotEmpty) ||
      lastVisitFilter != PatientLastVisitFilter.any;

  bool get hasSearchOrFilters => searchText.trim().isNotEmpty || hasActiveFilters;

  int get activeFilterCount {
    var count = 0;
    if (branchId != null && branchId!.isNotEmpty) {
      count++;
    }
    if (assignedDoctorId != null && assignedDoctorId!.isNotEmpty) {
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
    Object? assignedDoctorId = _sentinel,
    PatientLastVisitFilter? lastVisitFilter,
    PatientSortField? sortField,
    int? page,
    int? pageSize,
  }) {
    return PatientListFilters(
      searchText: searchText ?? this.searchText,
      branchId: identical(branchId, _sentinel) ? this.branchId : branchId as String?,
      assignedDoctorId: identical(assignedDoctorId, _sentinel) ? this.assignedDoctorId : assignedDoctorId as String?,
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
  const PatientTableRow({required this.item, this.assignedDoctorName});

  final PatientListItem item;
  final String? assignedDoctorName;

  String get displayId => PatientPresentationFormatting.displayId(item.id);

  DateTime? get lastVisitAt => item.lastVisitAt;

  DateTime? get nextAppointmentAt => item.nextAppointmentAt;

  int? get age => PatientPresentationFormatting.ageYears(item.dateOfBirth);

  String get ageGenderLabel => PatientPresentationFormatting.ageGenderLabel(age: age, gender: item.gender);

  static List<PatientTableRow> fromItems(List<PatientListItem> items) {
    return items.map((item) => PatientTableRow(item: item)).toList();
  }
}

/// Applies client-side filters that are not yet backed by `search_patients`.
List<PatientTableRow> applyClientFilters(List<PatientTableRow> rows, PatientListFilters filters) {
  var filtered = rows;

  if (filters.assignedDoctorId != null && filters.assignedDoctorId!.isNotEmpty) {
    filtered = filtered.where((row) => row.assignedDoctorName != null).toList(growable: false);
  }

  final now = DateTime.now();
  filtered = switch (filters.lastVisitFilter) {
    PatientLastVisitFilter.any => filtered,
    PatientLastVisitFilter.never => filtered.where((row) => row.lastVisitAt == null).toList(growable: false),
    PatientLastVisitFilter.last30Days =>
      filtered
          .where((row) => row.lastVisitAt != null && now.difference(row.lastVisitAt!).inDays <= 30)
          .toList(growable: false),
    PatientLastVisitFilter.last90Days =>
      filtered
          .where((row) => row.lastVisitAt != null && now.difference(row.lastVisitAt!).inDays <= 90)
          .toList(growable: false),
    PatientLastVisitFilter.over90Days =>
      filtered
          .where((row) => row.lastVisitAt != null && now.difference(row.lastVisitAt!).inDays > 90)
          .toList(growable: false),
  };

  final sorted = [...filtered];
  final searchText = filters.searchText.trim();
  sorted.sort((a, b) {
    if (searchText.isNotEmpty) {
      final rankCmp = _searchRelevanceRank(a, searchText).compareTo(_searchRelevanceRank(b, searchText));
      if (rankCmp != 0) {
        return rankCmp;
      }
    }

    return switch (filters.sortField) {
      PatientSortField.nameAsc => a.item.fullName.toLowerCase().compareTo(b.item.fullName.toLowerCase()),
      PatientSortField.nameDesc => b.item.fullName.toLowerCase().compareTo(a.item.fullName.toLowerCase()),
      PatientSortField.lastVisitAsc => _compareNullableDate(a.lastVisitAt, b.lastVisitAt),
      PatientSortField.lastVisitDesc => _compareNullableDate(b.lastVisitAt, a.lastVisitAt),
    };
  });
  return sorted;
}

/// Lower rank = better match. Prefix matches rank before substring matches.
int _searchRelevanceRank(PatientTableRow row, String searchText) {
  final query = searchText.toLowerCase();

  if (PatientSearchQuery.isPhonePrefixQuery(searchText)) {
    final phone = row.item.phone ?? '';
    return phone.startsWith(query) ? 0 : 1;
  }

  final name = row.item.fullName.toLowerCase();
  if (name.startsWith(query)) {
    return 0;
  }
  if (name.contains(query)) {
    return 1;
  }
  return 2;
}

int _compareNullableDate(DateTime? a, DateTime? b) {
  if (a == null && b == null) {
    return 0;
  }
  if (a == null) {
    return 1;
  }
  if (b == null) {
    return -1;
  }
  return a.compareTo(b);
}
