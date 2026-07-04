import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';

/// Donut chart of today's appointment counts grouped by status.
class DashboardStatusChart extends StatelessWidget {
  const DashboardStatusChart({
    required this.items,
    this.loading = false,
    super.key,
  });

  final List<AppointmentListItem> items;
  final bool loading;

  static const _statusOrder = <AppointmentStatus>[
    AppointmentStatus.confirmed,
    AppointmentStatus.scheduled,
    AppointmentStatus.checkedIn,
    AppointmentStatus.inProgress,
    AppointmentStatus.completed,
    AppointmentStatus.cancelled,
    AppointmentStatus.noShow,
  ];

  static List<AppChartSeries> seriesForItems(List<AppointmentListItem> items) {
    final counts = <AppointmentStatus, int>{};
    for (final item in items) {
      if (item.status == AppointmentStatus.unknown) {
        continue;
      }
      counts.update(item.status, (value) => value + 1, ifAbsent: () => 1);
    }

    return [
      for (final status in _statusOrder)
        if ((counts[status] ?? 0) > 0)
          AppChartSeries(
            name: status.label,
            points: [AppChartPoint(y: counts[status]!.toDouble())],
          ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final series = seriesForItems(items);
    final state = loading
        ? AppContentState.loading
        : series.isEmpty
        ? AppContentState.emptyFirstRun
        : AppContentState.ready;

    return AppAsyncStateView(
      state: state,
      config: const AppContentStateConfig(
        emptyFirstRunTitle: 'No appointments today',
        emptyFirstRunDescription: 'Status breakdown appears once appointments are scheduled.',
      ),
      child: AppChart(
        type: AppChartType.donut,
        series: series,
        height: AppSpacing.s20 * 2 + AppSpacing.s10,
        semanticsLabel: 'Appointment status breakdown',
      ),
    );
  }
}
