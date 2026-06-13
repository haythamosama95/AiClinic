import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/patients/presentation/models/patient_list_filters.dart';
import 'package:ai_clinic/features/patients/presentation/widgets/patients_filter_sidebar.dart';
import 'package:ai_clinic/features/patients/presentation/widgets/patients_sort_popover.dart';

/// Toolbar with search, filter, sort, and add-patient actions.
class PatientsToolbar extends StatelessWidget {
  const PatientsToolbar({
    required this.searchController,
    required this.filters,
    required this.onSearchChanged,
    required this.onFiltersChanged,
    this.onAddPatient,
    this.canCreate = true,
    super.key,
  });

  final TextEditingController searchController;
  final PatientListFilters filters;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<PatientListFilters> onFiltersChanged;
  final VoidCallback? onAddPatient;
  final bool canCreate;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: AppTextInput(
            controller: searchController,
            hintText: 'Search by name, ID, phone...',
            size: AppFieldSize.sm,
            prefixIcon: const Icon(Icons.search, size: 18),
            onChanged: onSearchChanged,
          ),
        ),
        const SizedBox(width: SpacingTokens.sm),
        PatientsFilterButton(filters: filters, onFiltersChanged: onFiltersChanged),
        const SizedBox(width: SpacingTokens.xs),
        PatientsSortButton(filters: filters, onFiltersChanged: onFiltersChanged),
        if (canCreate && onAddPatient != null) ...[
          const SizedBox(width: SpacingTokens.md),
          AppButton(
            label: 'Add New Patient',
            expand: false,
            size: AppFieldSize.sm,
            icon: const Icon(Icons.add, size: 18),
            onPressed: onAddPatient,
          ),
        ],
      ],
    );
  }
}
