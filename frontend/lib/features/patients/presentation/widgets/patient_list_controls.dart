import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/l10n/app_localizations_x.dart';
import 'package:ai_clinic/features/clinic-management/presentation/components/filter_menu_panel.dart';
import 'package:ai_clinic/features/clinic-management/presentation/components/list_control_bar.dart';
import 'package:ai_clinic/features/patients/domain/patient_last_visit_filter.dart';
import 'package:ai_clinic/features/patients/domain/patient_sort_field.dart';
import 'package:ai_clinic/features/patients/presentation/models/patient_list_filters.dart';
import 'package:ai_clinic/l10n/app_localizations.dart';

/// Search, sort, and last-visit filter controls (web `ListControlBar` top region).
class PatientListControls extends StatelessWidget {
  const PatientListControls({
    required this.filters,
    required this.onSearchChange,
    required this.onSortChange,
    required this.onLastVisitChange,
    this.activeFilters = const [],
    this.onClearAll,
    super.key,
  });

  final PatientListFilters filters;
  final ValueChanged<String> onSearchChange;
  final ValueChanged<PatientSortField> onSortChange;
  final ValueChanged<PatientLastVisitFilter> onLastVisitChange;
  final List<({String id, String label, VoidCallback onRemove})> activeFilters;
  final VoidCallback? onClearAll;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final lastVisitActive = filters.lastVisitFilter != PatientLastVisitFilter.any;

    return ListControlBar(
      searchPlaceholder: l10n.patientsListSearchPlaceholder,
      searchAriaLabel: l10n.patientsListSearchAriaLabel,
      searchQuery: filters.searchText,
      onSearchChange: onSearchChange,
      sortValue: filters.sortField.wireValue,
      defaultSortValue: PatientSortField.nameAsc.wireValue,
      sortOptions: [
        for (final field in PatientSortField.values)
          ListControlSortOption(value: field.wireValue, label: _sortLabel(l10n, field)),
      ],
      onSortChange: (value) => onSortChange(_sortFromWire(value)),
      onClearSort: filters.sortField != PatientSortField.nameAsc
          ? () => onSortChange(PatientSortField.nameAsc)
          : null,
      sortAriaLabel: l10n.patientsListSortAriaLabel,
      filterActiveCount: lastVisitActive ? 1 : 0,
      filterPanel: FilterMenuPanel(
        sections: [
          FilterMenuSection(
            id: 'lastVisit',
            label: l10n.patientsListLastVisitSection,
            value: filters.lastVisitFilter.wireValue,
            options: [
              for (final filter in PatientLastVisitFilter.values)
                FilterMenuOption(value: filter.wireValue, label: _lastVisitLabel(l10n, filter)),
            ],
            onChange: (value) => onLastVisitChange(_lastVisitFromWire(value)),
          ),
        ],
      ),
      activeFilterChips: [
        for (final chip in activeFilters) ListControlActiveFilterChip(id: chip.id, label: chip.label),
      ],
      onRemoveChip: (id) {
        for (final chip in activeFilters) {
          if (chip.id == id) {
            chip.onRemove();
            return;
          }
        }
      },
      onClearAllFilters: onClearAll,
    );
  }
}

PatientSortField _sortFromWire(String value) {
  return PatientSortField.values.firstWhere(
    (field) => field.wireValue == value,
    orElse: () => PatientSortField.nameAsc,
  );
}

PatientLastVisitFilter _lastVisitFromWire(String value) {
  return PatientLastVisitFilter.values.firstWhere(
    (filter) => filter.wireValue == value,
    orElse: () => PatientLastVisitFilter.any,
  );
}

String _sortLabel(AppLocalizations l10n, PatientSortField field) {
  return switch (field) {
    PatientSortField.nameAsc => l10n.patientsListSortNameAsc,
    PatientSortField.nameDesc => l10n.patientsListSortNameDesc,
    PatientSortField.lastVisitDesc => l10n.patientsListSortLastVisitNewest,
    PatientSortField.lastVisitAsc => l10n.patientsListSortLastVisitOldest,
  };
}

String _lastVisitLabel(AppLocalizations l10n, PatientLastVisitFilter filter) {
  return switch (filter) {
    PatientLastVisitFilter.any => l10n.patientsListLastVisitAny,
    PatientLastVisitFilter.last30Days => l10n.patientsListLastVisit30Days,
    PatientLastVisitFilter.last90Days => l10n.patientsListLastVisit90Days,
    PatientLastVisitFilter.over90Days => l10n.patientsListLastVisitOver90Days,
    PatientLastVisitFilter.never => l10n.patientsListLastVisitNever,
  };
}
