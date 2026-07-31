import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:ai_clinic/core/ui/components/app_data_table.dart';
import 'package:ai_clinic/core/ui/components/app_empty_state.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
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

  @override
  Widget build(BuildContext context) {
    final sorted = queueSortForTriage(appointments, now);

    if (sorted.isEmpty) {
      return _buildEmptyState(context);
    }

    final colors = context.appColors;

    return AppDataTable<AppointmentListItem>(
      ariaLabel: "Today's appointments",
      animateRows: true,
      density: TableDensity.comfortable,
      headerTextStyle: AppTypography.caption(context).copyWith(
        fontWeight: FontWeight.w600,
        color: colors.textTertiary,
      ),
      columns: [
        TableColumn(
          id: 'patient',
          header: 'Patient',
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
          accessor: (item) => _overdueCell(
            context,
            item,
            now: now,
            child: Text(
              AppointmentQueueDisplay.queueDoctorLabel(
                item,
                shiftLookup: shiftLookup,
              ),
              style: AppTypography.bodySm(context).copyWith(
                color: colors.textSecondary,
              ),
            ),
          ),
        ),
        TableColumn(
          id: 'type',
          header: 'Type',
          accessor: (item) => _overdueCell(
            context,
            item,
            now: now,
            child: Text(
              item.type.label,
              style: AppTypography.bodySm(context).copyWith(
                color: colors.textSecondary,
              ),
            ),
          ),
        ),
        TableColumn(
          id: 'wait',
          header: 'Wait',
          accessor: (item) => _overdueCell(
            context,
            item,
            now: now,
            child: _WaitCell(item: item, now: now),
          ),
        ),
        TableColumn(
          id: 'actions',
          header: 'Actions',
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
    return queueIsOverdue(item, now) &&
        item.status == AppointmentStatus.scheduled;
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
        border: isFirstColumn
            ? Border(
                left: BorderSide(color: colors.statusDangerFg, width: 4),
              )
            : null,
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
          style: AppTypography.bodySm(context).copyWith(
            fontWeight: FontWeight.w500,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          item.patientMrn ?? '—',
          style: AppTypography.mono(context).copyWith(
            fontSize: 12,
            color: colors.textSecondary,
          ),
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
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          QueueAppointmentsTable._timeFormat.format(item.startTime),
          style: AppTypography.mono(context).copyWith(color: colors.textPrimary),
        ),
        if (overdue) ...[
          const SizedBox(height: 2),
          Text(
            '${now.difference(item.startTime).inMinutes}m overdue',
            style: AppTypography.bodySm(context).copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: colors.statusDangerFg,
            ),
          ),
        ],
      ],
    );
  }
}

class _WaitCell extends StatelessWidget {
  const _WaitCell({required this.item, required this.now});

  final AppointmentListItem item;
  final DateTime now;

  static const _showWaitStatuses = <AppointmentStatus>{
    AppointmentStatus.checkedIn,
    AppointmentStatus.inProgress,
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    if (!_showWaitStatuses.contains(item.status)) {
      return Text(
        '—',
        style: AppTypography.mono(context).copyWith(
          color: colors.textPlaceholder,
        ),
      );
    }

    final (label, tier) = AppointmentQueueDisplay.waitPresentation(
      item,
      now: now,
    );

    final color = switch (tier) {
      AppointmentQueueWaitTier.critical => colors.statusDangerFg,
      AppointmentQueueWaitTier.warning => colors.statusWarningFg,
      AppointmentQueueWaitTier.normal => colors.textPrimary,
    };

    final fontWeight = switch (tier) {
      AppointmentQueueWaitTier.critical => FontWeight.w600,
      AppointmentQueueWaitTier.warning => FontWeight.w500,
      AppointmentQueueWaitTier.normal => FontWeight.w400,
    };

    return Text(
      label,
      style: AppTypography.mono(context).copyWith(
        color: color,
        fontWeight: fontWeight,
      ),
    );
  }
}
