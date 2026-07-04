import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/navigation/app_navigator.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_org_calendar.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_queue_display.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_queue_provider.dart';
import 'package:ai_clinic/features/dashboard/presentation/widgets/dashboard_status_chart.dart';
import 'package:ai_clinic/features/dashboard/presentation/widgets/dashboard_upcoming_appointments_table.dart';

/// Clinic home dashboard — operational overview for the active branch.
///
/// Composes [DashboardPattern] with metrics and tables bound to existing
/// appointment queue providers. Revenue and outstanding balances are omitted
/// until dedicated summary providers exist.
class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authSessionProvider);
    final canAccessAppointments = AuthRouteGuard.canAccessAppointmentHub(auth);
    final canBookAppointments = AuthRouteGuard.canAccessAppointmentBooking(auth);
    final queueState = ref.watch(appointmentQueueProvider);

    final timezone = effectiveOrganizationTimezone(auth.context?.organizationTimezone);
    final stats = AppointmentQueueDisplay.computeStats(
      queueState.items,
      now: DateTime.now(),
      comparisonItems: queueState.comparisonItems,
      comparisonNow: queueState.comparisonNow,
    );
    final hasComparison = queueState.comparisonItems != null && !queueState.comparisonUnavailable;
    final comparisonCaption = hasComparison ? 'vs yesterday' : null;

    return DashboardPattern(
      title: 'Dashboard',
      description: _dashboardDescription(auth),
      actions: _buildHeaderActions(
        context,
        canBookAppointments: canBookAppointments,
        canAccessAppointments: canAccessAppointments,
      ),
      metrics: [
        _buildAppointmentsMetric(
          stats: stats,
          loading: canAccessAppointments && queueState.loading && queueState.items.isEmpty,
          unavailable: !canAccessAppointments,
          comparisonCaption: comparisonCaption,
        ),
        const _UnavailableMetricCard(
          label: 'Revenue today',
          caption: 'Revenue summary not available',
        ),
        _buildPatientsSeenMetric(
          stats: stats,
          loading: canAccessAppointments && queueState.loading && queueState.items.isEmpty,
          unavailable: !canAccessAppointments,
          comparisonCaption: comparisonCaption,
        ),
        const _UnavailableMetricCard(
          label: 'Outstanding',
          caption: 'EGP unpaid · summary not available',
        ),
      ],
      charts: [
        DashboardChartSlot(
          title: 'Weekly revenue',
          chart: const AppAsyncStateView(
            state: AppContentState.emptyFirstRun,
            config: AppContentStateConfig(
              emptyFirstRunTitle: 'No revenue data',
              emptyFirstRunDescription: 'Weekly revenue tracking is not available yet.',
            ),
            child: SizedBox.shrink(),
          ),
        ),
        DashboardChartSlot(
          title: 'Appointments by status',
          chart: canAccessAppointments
              ? DashboardStatusChart(
                  items: queueState.items,
                  loading: queueState.loading && queueState.items.isEmpty,
                )
              : const AppAsyncStateView(
                  state: AppContentState.noAccess,
                  config: AppContentStateConfig(
                    noAccessTitle: 'Appointments by status',
                    noAccessDescription: 'You do not have permission to view appointment data.',
                  ),
                  child: SizedBox.shrink(),
                ),
        ),
      ],
      tables: [
        DashboardTableSlot(
          title: 'Upcoming appointments',
          description: 'Today\'s schedule for the active branch.',
          actions: canAccessAppointments
              ? AppButton(
                  label: 'View queue',
                  variant: AppButtonVariant.ghost,
                  size: AppButtonSize.sm,
                  onPressed: () => context.nav.goAppointmentsQueue(),
                )
              : null,
          table: canAccessAppointments
              ? DashboardUpcomingAppointmentsTable(
                  items: queueState.items,
                  organizationTimezone: timezone,
                  loading: queueState.loading && queueState.items.isEmpty,
                  error: queueState.error,
                  onRetry: () => ref.read(appointmentQueueProvider.notifier).refresh(),
                )
              : const AppAsyncStateView(
                  state: AppContentState.noAccess,
                  config: AppContentStateConfig(
                    noAccessTitle: 'Upcoming appointments',
                    noAccessDescription: 'You do not have permission to view the appointment queue.',
                  ),
                  child: SizedBox.shrink(),
                ),
        ),
      ],
    );
  }

  static String? _dashboardDescription(AuthSessionState auth) {
    final fullName = auth.context?.staffProfile.fullName.trim();
    if (fullName == null || fullName.isEmpty) {
      return 'Operational overview for your clinic.';
    }

    final firstName = fullName.split(RegExp(r'\s+')).first;
    return 'Welcome back, $firstName. Operational overview for your clinic.';
  }

  static Widget? _buildHeaderActions(
    BuildContext context, {
    required bool canBookAppointments,
    required bool canAccessAppointments,
  }) {
    if (!canBookAppointments && !canAccessAppointments) {
      return null;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (canBookAppointments)
          AppButton(
            label: 'Book appointment',
            leadingIcon: LucideIcons.plus,
            onPressed: () => context.nav.goAppointmentsBook(),
          ),
        if (canBookAppointments && canAccessAppointments) const SizedBox(width: AppSpacing.s2),
        if (canAccessAppointments)
          AppButton(
            label: 'View queue',
            variant: AppButtonVariant.secondary,
            leadingIcon: LucideIcons.listOrdered,
            onPressed: () => context.nav.goAppointmentsQueue(),
          ),
      ],
    );
  }

  static Widget _buildAppointmentsMetric({
    required AppointmentQueueStats stats,
    required bool loading,
    required bool unavailable,
    required String? comparisonCaption,
  }) {
    if (unavailable) {
      return const _UnavailableMetricCard(
        label: 'Today\'s appointments',
        caption: 'Appointment access required',
      );
    }

    return AppMetricCard(
      label: 'Today\'s appointments',
      value: loading ? '—' : '${stats.total}',
      delta: loading ? null : _metricDelta(stats.totalTrend, upIsPositive: true),
      caption: comparisonCaption,
    );
  }

  static Widget _buildPatientsSeenMetric({
    required AppointmentQueueStats stats,
    required bool loading,
    required bool unavailable,
    required String? comparisonCaption,
  }) {
    if (unavailable) {
      return const _UnavailableMetricCard(
        label: 'Patients seen',
        caption: 'Appointment access required',
      );
    }

    return AppMetricCard(
      label: 'Patients seen',
      value: loading ? '—' : '${stats.completed}',
      delta: loading ? null : _metricDelta(stats.completedTrend, upIsPositive: true),
      caption: comparisonCaption,
    );
  }

  static AppMetricDelta? _metricDelta(
    AppointmentQueueStatTrend? trend, {
    required bool upIsPositive,
  }) {
    final change = trend?.percentChange;
    if (change == null) {
      return null;
    }

    final direction = change >= 0 ? AppMetricDeltaDirection.up : AppMetricDeltaDirection.down;
    return AppMetricDelta(
      value: '${change.abs().round()}%',
      direction: direction,
      positive: upIsPositive ? change >= 0 : change <= 0,
    );
  }
}

/// Metric placeholder when no safe provider exists for the value.
class _UnavailableMetricCard extends StatelessWidget {
  const _UnavailableMetricCard({
    required this.label,
    required this.caption,
  });

  final String label;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return AppMetricCard(
      label: label,
      value: '—',
      caption: caption,
    );
  }
}
