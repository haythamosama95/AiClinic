import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/features/patients/presentation/models/patient_list_filters.dart';
import 'package:ai_clinic/features/patients/presentation/utils/patient_presentation_formatting.dart';

/// Builds [AppTable] columns for the patients list.
List<AppTableColumn<PatientTableRow>> buildPatientTableColumns(BuildContext context) {
  final typography = context.typography;
  final colors = context.colors;

  return [
    AppTableColumn(
      id: 'patient',
      header: 'Patient',
      flex: 3,
      sticky: true,
      sortable: true,
      cellBuilder: (context, row) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              row.item.fullName,
              style: typography.bodyStrong.copyWith(color: colors.textPrimary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              'MRN · ${row.displayId}',
              style: typography.tabular(typography.caption).copyWith(color: colors.textSecondary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        );
      },
    ),
    AppTableColumn(
      id: 'ageGender',
      header: 'Age/Gender',
      width: 108,
      cellBuilder: (context, row) => Text(row.ageGenderLabel, maxLines: 1, overflow: TextOverflow.ellipsis),
    ),
    AppTableColumn(
      id: 'phone',
      header: 'Contact',
      width: 132,
      cellBuilder: (context, row) => Text(
        PatientPresentationFormatting.orDash(row.item.phone),
        style: typography.tabular(typography.bodySm),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    ),
    AppTableColumn(
      id: 'branch',
      header: 'Branch',
      flex: 2,
      cellBuilder: (context, row) => Text(row.item.registeringBranchName, maxLines: 1, overflow: TextOverflow.ellipsis),
    ),
    AppTableColumn(
      id: 'lastVisit',
      header: 'Last visit',
      width: 112,
      sortable: true,
      cellBuilder: (context, row) {
        final lastVisit = row.lastVisitAt;
        return Text(
          lastVisit == null ? '—' : PatientPresentationFormatting.date.format(lastVisit),
          style: typography.tabular(typography.bodySm),
        );
      },
    ),
    AppTableColumn(
      id: 'nextAppointment',
      header: 'Next appointment',
      width: 148,
      cellBuilder: (context, row) {
        final next = row.nextAppointmentAt;
        if (next == null) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(
                icon: LucideIcons.calendarPlus,
                dimension: AppSpacing.s3 + AppSpacing.s0_5,
                color: colors.iconMuted,
              ),
              const SizedBox(width: AppSpacing.s1),
              Text('Schedule', style: typography.caption.copyWith(color: colors.textTertiary)),
            ],
          );
        }
        return AppBadge(
          size: AppBadgeSize.sm,
          color: AppBadgeColor.info,
          child: Text(
            PatientPresentationFormatting.dateTime.format(next.toLocal()),
            style: typography.tabular(typography.caption),
          ),
        );
      },
    ),
  ];
}

/// Maps table sort state to server-backed [PatientSortField].
PatientSortField? patientSortFieldForColumn(String? columnId, AppTableSortDirection? direction) {
  if (columnId == null || direction == null) {
    return null;
  }
  return switch (columnId) {
    'patient' => direction == AppTableSortDirection.ascending ? PatientSortField.nameAsc : PatientSortField.nameDesc,
    'lastVisit' =>
      direction == AppTableSortDirection.ascending ? PatientSortField.lastVisitAsc : PatientSortField.lastVisitDesc,
    _ => null,
  };
}

(String?, AppTableSortDirection?) patientTableSortState(PatientSortField sortField) {
  return switch (sortField) {
    PatientSortField.nameAsc => ('patient', AppTableSortDirection.ascending),
    PatientSortField.nameDesc => ('patient', AppTableSortDirection.descending),
    PatientSortField.lastVisitAsc => ('lastVisit', AppTableSortDirection.ascending),
    PatientSortField.lastVisitDesc => ('lastVisit', AppTableSortDirection.descending),
  };
}
