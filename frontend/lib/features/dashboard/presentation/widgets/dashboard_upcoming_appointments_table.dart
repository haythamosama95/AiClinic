import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:ai_clinic/app/navigation/app_navigator.dart';
import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_org_calendar.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/dashboard/presentation/widgets/dashboard_appointment_badge.dart';

/// Today's upcoming appointments table for the home dashboard.
class DashboardUpcomingAppointmentsTable extends StatelessWidget {
  const DashboardUpcomingAppointmentsTable({
    required this.items,
    required this.organizationTimezone,
    this.loading = false,
    this.error,
    this.onRetry,
    super.key,
  });

  final List<AppointmentListItem> items;
  final String organizationTimezone;
  final bool loading;
  final Object? error;
  final VoidCallback? onRetry;

  static final _timeFormat = DateFormat('h:mm a');

  static List<AppointmentListItem> upcomingItems(List<AppointmentListItem> source) {
    final upcoming = source
        .where(
          (item) =>
              item.status != AppointmentStatus.cancelled &&
              item.status != AppointmentStatus.noShow &&
              item.status != AppointmentStatus.completed &&
              item.status != AppointmentStatus.unknown,
        )
        .toList(growable: false);
    upcoming.sort((a, b) => a.startTime.compareTo(b.startTime));
    return upcoming;
  }

  String _formatTime(AppointmentListItem item) {
    final wallClock = appointmentWallClockInOrganizationTimezone(
      organizationTimezone,
      item.startTime,
    );
    return _timeFormat.format(wallClock);
  }

  @override
  Widget build(BuildContext context) {
    final rows = upcomingItems(items);

    return AppTable<AppointmentListItem>(
      columns: [
        AppTableColumn(
          id: 'time',
          header: 'Time',
          cellBuilder: (context, row) => Text(
            _formatTime(row),
            style: context.typography.tabular(context.typography.body),
          ),
        ),
        AppTableColumn(
          id: 'patient',
          header: 'Patient',
          cellBuilder: (context, row) => Text(row.patientName),
        ),
        AppTableColumn(
          id: 'doctor',
          header: 'Doctor',
          cellBuilder: (context, row) => Text(row.doctorDisplayName),
        ),
        AppTableColumn(
          id: 'status',
          header: 'Status',
          cellBuilder: (context, row) => DashboardAppointmentBadge(status: row.status),
        ),
      ],
      rowId: (row) => row.id,
      data: rows,
      loading: loading,
      error: error,
      onRetry: onRetry,
      filteredEmpty: !loading && error == null && rows.isEmpty,
      onRowTap: (row) => context.nav.pushAppointmentDetail(row.id, preview: row),
      emptyState: const AppEmptyState(
        variant: AppEmptyStateVariant.firstRun,
        title: 'No upcoming appointments',
        description: 'Today\'s schedule is clear.',
      ),
      semanticLabel: 'Upcoming appointments',
    );
  }
}
