import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/components/app_avatar.dart';
import 'package:ai_clinic/core/ui/components/app_data_table.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
import 'package:ai_clinic/features/patients/presentation/models/patient_list_filters.dart';
import 'package:ai_clinic/features/patients/presentation/utils/patient_presentation_formatting.dart';

/// Patients list table backed by [AppDataTable].
class PatientTable extends StatelessWidget {
  const PatientTable({
    required this.rows,
    required this.loading,
    this.onRowClick,
    this.emptyState,
    this.errorState,
    this.loadingRows = 5,
    super.key,
  });

  final List<PatientTableRow> rows;
  final bool loading;
  final ValueChanged<PatientTableRow>? onRowClick;
  final Widget? emptyState;
  final Widget? errorState;
  final int loadingRows;

  static const _tabularFigures = [FontFeature.tabularFigures()];

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return AppDataTable<PatientTableRow>(
      ariaLabel: 'Patients',
      density: TableDensity.comfortable,
      animateRows: true,
      headerTextStyle: AppTypography.caption(context).copyWith(fontWeight: FontWeight.w600, color: colors.textTertiary),
      columns: [
        TableColumn(
          id: 'patient',
          header: 'Patient',
          accessor: (row) => _PatientCell(name: row.item.fullName),
        ),
        TableColumn(
          id: 'phone',
          header: 'Phone',
          accessor: (row) => Text(
            PatientPresentationFormatting.orDash(row.item.phone),
            style: AppTypography.bodySm(context).copyWith(color: colors.textSecondary, fontFeatures: _tabularFigures),
          ),
        ),
        TableColumn(
          id: 'dob',
          header: 'DOB',
          accessor: (row) => Text(
            PatientPresentationFormatting.dateOfBirthLabel(row.item.dateOfBirth),
            style: AppTypography.bodySm(context).copyWith(fontFeatures: _tabularFigures),
          ),
        ),
        TableColumn(
          id: 'lastVisit',
          header: 'Last visit',
          align: TableAlign.end,
          accessor: (row) => Text(
            row.item.lastVisitAt != null ? PatientPresentationFormatting.date.format(row.item.lastVisitAt!) : '—',
            style: AppTypography.bodySm(context).copyWith(color: colors.textSecondary, fontFeatures: _tabularFigures),
          ),
        ),
        TableColumn(
          id: 'nextVisit',
          header: 'Next visit',
          align: TableAlign.end,
          accessor: (row) => Text(
            row.item.nextAppointmentAt != null
                ? PatientPresentationFormatting.dateTime.format(row.item.nextAppointmentAt!)
                : '—',
            style: AppTypography.bodySm(context).copyWith(color: colors.textSecondary, fontFeatures: _tabularFigures),
          ),
        ),
      ],
      data: rows,
      getRowId: (row) => row.item.id,
      loading: loading,
      loadingRows: loadingRows,
      emptyState: emptyState,
      errorState: errorState,
      onRowClick: onRowClick,
    );
  }
}

class _PatientCell extends StatelessWidget {
  const _PatientCell({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Row(
      children: [
        AppAvatar(name: name, size: AvatarSize.sm),
        const SizedBox(width: AppSpacing.space3),
        Expanded(
          child: Text(
            name,
            style: AppTypography.bodyStrong(context).copyWith(color: colors.textPrimary),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
