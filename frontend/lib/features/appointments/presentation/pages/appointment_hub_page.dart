import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/navigation/app_navigator.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_queue_display.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_queue_shift_doctors.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_calendar_provider.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_queue_provider.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_queue_shift_provider.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_calendar_panel.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_queue_board.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_queue_stats_banner.dart';
import 'package:ai_clinic/features/settings/domain/branch_list_item.dart';

/// Appointments hub with queue board and calendar switch (`/appointments`).
class AppointmentHubPage extends ConsumerStatefulWidget {
  const AppointmentHubPage({super.key});

  @override
  ConsumerState<AppointmentHubPage> createState() => _AppointmentHubPageState();
}

class _AppointmentHubPageState extends ConsumerState<AppointmentHubPage> {
  var _view = CalendarQueueView.queue;

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authSessionProvider);
    if (!AuthRouteGuard.canAccessAppointmentHub(auth)) {
      return const AppEmptyState(
        variant: AppEmptyStateVariant.noAccess,
        title: 'Appointments',
        description: 'You do not have permission to access appointments.',
      );
    }

    final canBook = AuthRouteGuard.canAccessAppointmentBooking(auth);
    final queueState = ref.watch(appointmentQueueProvider);
    final shiftLookupAsync = ref.watch(appointmentQueueShiftDoctorLookupProvider);
    final branches = ref.watch(appointmentCalendarBranchesProvider).maybeWhen(
      data: (items) => items,
      orElse: () => const <BranchListItem>[],
    );
    final branchLabel = _branchLabel(branches, auth.context?.activeBranchId);
    final now = clock.now();
    final stats = AppointmentQueueDisplay.computeStats(
      queueState.items,
      now: now,
      comparisonItems: queueState.comparisonItems,
      comparisonNow: queueState.comparisonNow,
    );

    final contentState = switch (true) {
      _ when queueState.loading && queueState.items.isEmpty => AppContentState.loading,
      _ when queueState.error != null && queueState.items.isEmpty => AppContentState.error,
      _ => AppContentState.ready,
    };

    return AppAsyncStateView(
      state: contentState,
      config: AppContentStateConfig(
        errorMessage: queueState.error,
        onRetry: ref.read(appointmentQueueProvider.notifier).refresh,
        loadingLabel: "Loading today's queue…",
      ),
      child: CalendarQueuePattern(
        view: _view,
        onViewChanged: (view) => setState(() => _view = view),
        toolbarStart: AppPageHeader(
          title: 'Appointments',
          description: 'Scheduling at $branchLabel',
        ),
        toolbarEnd: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (canBook)
              AppButton(
                key: const Key('appointments_hub_book'),
                label: 'Book',
                size: AppButtonSize.sm,
                leadingIcon: LucideIcons.plus,
                onPressed: () => context.nav.goAppointmentsBook(),
              ),
            const SizedBox(width: AppSpacing.s2),
            AppButton(
              key: const Key('appointments_hub_queue'),
              label: 'Queue',
              variant: AppButtonVariant.secondary,
              size: AppButtonSize.sm,
              onPressed: () => context.nav.goAppointmentsQueue(),
            ),
            const SizedBox(width: AppSpacing.s2),
            AppButton(
              key: const Key('appointments_hub_calendar'),
              label: 'Calendar',
              variant: AppButtonVariant.ghost,
              size: AppButtonSize.sm,
              onPressed: () => context.nav.goAppointmentsCalendar(),
            ),
          ],
        ),
        queueHeader: AppointmentQueueStatsBanner(
          stats: stats,
          trendsUnavailable: queueState.comparisonUnavailable,
        ),
        queueColumns: buildAppointmentQueueColumns(
          context: context,
          items: queueState.items,
          branchLabel: branchLabel,
          shiftLookup: shiftLookupAsync.value ?? AppointmentQueueShiftDoctorLookup.empty,
          now: now,
        ),
        calendar: const SizedBox(
          height: 560,
          child: AppointmentCalendarPanel(showFilters: false, title: 'Day schedule'),
        ),
      ),
    );
  }

  String _branchLabel(List<BranchListItem> branches, String? branchId) {
    if (branchId == null) {
      return 'your active branch';
    }
    for (final branch in branches) {
      if (branch.id == branchId) {
        return branch.name;
      }
    }
    return 'your active branch';
  }
}
