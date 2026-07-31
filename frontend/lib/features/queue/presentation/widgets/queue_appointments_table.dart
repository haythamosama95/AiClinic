import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:ai_clinic/app/navigation/app_navigator.dart';
import 'package:ai_clinic/core/ui/components/app_data_table.dart';
import 'package:ai_clinic/core/ui/components/app_empty_state.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_today_range.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/queue/domain/queue_display.dart';
import 'package:ai_clinic/features/queue/domain/queue_shift_doctors.dart';
import 'package:ai_clinic/features/queue/presentation/widgets/queue_row_actions.dart';
import 'package:ai_clinic/features/queue/presentation/widgets/queue_secretary_utils.dart';
import 'package:ai_clinic/features/queue/presentation/widgets/queue_status_badge.dart';

/// Triage appointments table for the queue main column (web `AppointmentsTable`).
class QueueAppointmentsTable extends StatelessWidget {
  const QueueAppointmentsTable({
    required this.appointments,
    required this.siblingAppointments,
    required this.shiftLookup,
    required this.now,
    required this.onTransition,
    this.organizationTimezone = 'UTC',
    this.referenceUtc,
    super.key,
  });

  final List<AppointmentListItem> appointments;
  final List<AppointmentListItem> siblingAppointments;
  final AppointmentQueueShiftDoctorLookup shiftLookup;
  final DateTime now;
  final QueueAppointmentTransitionCallback onTransition;
  final String organizationTimezone;
  final DateTime? referenceUtc;

  static final _timeFormat = DateFormat('h:mm a');

  static const _cellHorizontalPadding = AppSpacing.space3 * 2;
  static const _overdueBorderWidth = 4.0;

  static double _measureTextWidth(BuildContext context, String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      maxLines: 1,
    )..layout();
    return painter.width;
  }

  static double _patientColumnWidth(BuildContext context, List<AppointmentListItem> items) {
    final headerStyle = AppTypography.caption(context).copyWith(fontWeight: FontWeight.w600);
    final nameStyle = AppTypography.bodySm(context).copyWith(fontWeight: FontWeight.w500);
    final mrnStyle = AppTypography.mono(context).copyWith(fontSize: 12);

    var maxContent = _measureTextWidth(context, 'Patient', headerStyle);
    for (final item in items) {
      maxContent = math.max(maxContent, _measureTextWidth(context, item.patientName, nameStyle));
      maxContent = math.max(maxContent, _measureTextWidth(context, item.patientMrn ?? '—', mrnStyle));
    }

    return math.max(160, maxContent.ceilToDouble() + _cellHorizontalPadding + _overdueBorderWidth);
  }

  static double _doctorColumnWidth(
    BuildContext context,
    List<AppointmentListItem> items,
    AppointmentQueueShiftDoctorLookup shiftLookup,
  ) {
    final headerStyle = AppTypography.caption(context).copyWith(fontWeight: FontWeight.w600);
    final labelStyle = AppTypography.bodySm(context);

    var maxContent = _measureTextWidth(context, 'Preferred doctor', headerStyle);
    for (final item in items) {
      final label = AppointmentQueueDisplay.queueDoctorLabel(item, shiftLookup: shiftLookup);
      maxContent = math.max(maxContent, _measureTextWidth(context, label, labelStyle));
    }

    return math.max(160, maxContent.ceilToDouble() + _cellHorizontalPadding);
  }

  @override
  Widget build(BuildContext context) {
    final sorted = sortAppointmentsByStartTime(appointments);

    if (sorted.isEmpty) {
      return _buildEmptyState(context);
    }

    final colors = context.appColors;
    final patientColumnWidth = _patientColumnWidth(context, sorted);
    final doctorColumnWidth = _doctorColumnWidth(context, sorted, shiftLookup);

    return AppDataTable<AppointmentListItem>(
      ariaLabel: "Today's appointments",
      animateRows: true,
      density: TableDensity.comfortable,
      rowHeightOverride: 56,
      headerTextStyle: AppTypography.caption(context).copyWith(fontWeight: FontWeight.w600, color: colors.textTertiary),
      columns: [
        TableColumn(
          id: 'patient',
          header: 'Patient',
          align: TableAlign.start,
          width: patientColumnWidth,
          minWidth: 160,
          accessor: (item) => _overdueCell(
            context,
            item,
            now: now,
            isFirstColumn: true,
            child: _PatientCell(item: item),
          ),
        ),
        TableColumn(
          id: 'time',
          header: 'Time',
          align: TableAlign.center,
          minWidth: 112,
          accessor: (item) => _overdueCell(
            context,
            item,
            now: now,
            child: _TimeCell(item: item, now: now),
          ),
        ),
        TableColumn(
          id: 'status',
          header: 'Status',
          align: TableAlign.center,
          minWidth: 120,
          accessor: (item) => _overdueCell(
            context,
            item,
            now: now,
            child: QueueStatusBadge(status: item.status),
          ),
        ),
        TableColumn(
          id: 'doctor',
          header: 'Preferred doctor',
          align: TableAlign.start,
          width: doctorColumnWidth,
          minWidth: 160,
          accessor: (item) => _overdueCell(
            context,
            item,
            now: now,
            child: Text(
              AppointmentQueueDisplay.queueDoctorLabel(item, shiftLookup: shiftLookup),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.bodySm(context).copyWith(color: colors.textSecondary),
            ),
          ),
        ),
        TableColumn(
          id: 'actions',
          header: 'Actions',
          align: TableAlign.center,
          minWidth: 180,
          accessor: (item) => _overdueCell(
            context,
            item,
            now: now,
            child: QueueRowActions(
              appointment: item,
              siblingAppointments: siblingAppointments,
              shiftLookup: shiftLookup,
              onTransition: onTransition,
              organizationTimezone: organizationTimezone,
              referenceUtc: referenceUtc,
            ),
          ),
        ),
      ],
      data: sorted,
      getRowId: (item) => item.id,
      onRowClick: (item) => context.nav.pushAppointmentDetail(item.id, preview: item),
      emptyState: _buildEmptyState(context),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final colors = context.appColors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceDefault,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: colors.borderDefault),
      ),
      child: AppEmptyState(
        variant: AppEmptyStateVariant.noResults,
        title: 'No appointments match your filters',
        description: 'Try adjusting search or status filters',
      ),
    );
  }

  static bool _isOverdueScheduled(AppointmentListItem item, DateTime now) {
    return queueIsOverdue(item, now) && item.status == AppointmentStatus.scheduled;
  }

  static Widget _overdueCell(
    BuildContext context,
    AppointmentListItem item, {
    required DateTime now,
    required Widget child,
    bool isFirstColumn = false,
  }) {
    if (!_isOverdueScheduled(item, now)) {
      return child;
    }

    final colors = context.appColors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.statusDangerSurface.withValues(alpha: 0.3),
        border: isFirstColumn ? Border(left: BorderSide(color: colors.statusDangerFg, width: 4)) : null,
      ),
      child: child,
    );
  }
}

class _PatientCell extends StatelessWidget {
  const _PatientCell({required this.item});

  final AppointmentListItem item;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          item.patientName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.bodySm(context).copyWith(fontWeight: FontWeight.w500, color: colors.textPrimary),
        ),
        const SizedBox(height: 2),
        Text(
          item.patientMrn ?? '—',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.mono(context).copyWith(fontSize: 12, color: colors.textSecondary),
        ),
      ],
    );
  }
}

class _TimeCell extends StatelessWidget {
  const _TimeCell({required this.item, required this.now});

  final AppointmentListItem item;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final overdue = QueueAppointmentsTable._isOverdueScheduled(item, now);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          QueueAppointmentsTable._timeFormat.format(item.startTime),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.mono(context).copyWith(color: colors.textPrimary),
        ),
        if (overdue) ...[
          const SizedBox(height: 2),
          Text(
            '${now.difference(item.startTime).inMinutes}m overdue',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodySm(
              context,
            ).copyWith(fontSize: 12, fontWeight: FontWeight.w500, color: colors.statusDangerFg),
          ),
        ],
      ],
    );
  }
}
