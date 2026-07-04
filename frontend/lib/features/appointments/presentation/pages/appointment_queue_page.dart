import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/features/appointments/data/appointment_queue_realtime.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_queue_display.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_queue_shift_doctors.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_calendar_provider.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_queue_provider.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_queue_shift_provider.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_queue_board.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_queue_stats_banner.dart';
import 'package:ai_clinic/features/settings/domain/branch_list_item.dart';

/// Clinic queue dashboard for front-desk flow management (`/appointments/queue`).
class AppointmentQueuePage extends ConsumerStatefulWidget {
  const AppointmentQueuePage({super.key});

  @override
  ConsumerState<AppointmentQueuePage> createState() => _AppointmentQueuePageState();
}

class _AppointmentQueuePageState extends ConsumerState<AppointmentQueuePage> {
  Timer? _clockTimer;
  DateTime _now = clock.now();

  @override
  void initState() {
    super.initState();
    _clockTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) {
        setState(() => _now = clock.now());
      }
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authSessionProvider);
    if (!AuthRouteGuard.canAccessAppointmentHub(auth)) {
      return const AppEmptyState(
        variant: AppEmptyStateVariant.noAccess,
        title: 'Queue',
        description: 'You need appointment permissions to view the clinic queue.',
      );
    }

    final state = ref.watch(appointmentQueueProvider);
    final controller = ref.read(appointmentQueueProvider.notifier);
    final shiftLookupAsync = ref.watch(appointmentQueueShiftDoctorLookupProvider);
    final branches = ref.watch(appointmentCalendarBranchesProvider).maybeWhen(
      data: (items) => items,
      orElse: () => const <BranchListItem>[],
    );
    final branchLabel = _branchLabel(branches, auth.context?.activeBranchId);
    final stats = AppointmentQueueDisplay.computeStats(
      state.items,
      now: _now,
      comparisonItems: state.comparisonItems,
      comparisonNow: state.comparisonNow,
    );
    final degraded = state.realtimeConnection == AppointmentQueueRealtimeConnection.degraded;

    final contentState = switch (true) {
      _ when state.loading && state.items.isEmpty => AppContentState.loading,
      _ when state.error != null && state.items.isEmpty => AppContentState.error,
      _ when degraded => AppContentState.degraded,
      _ => AppContentState.ready,
    };

    return AppAsyncStateView(
      state: contentState,
      config: AppContentStateConfig(
        loadingLabel: "Loading today's queue…",
        errorMessage: state.error,
        onRetry: controller.refresh,
        degradedTitle: 'Live updates paused',
        degradedBody: 'The queue is showing the last loaded data. Pull to refresh or retry.',
        onDegradedDismiss: controller.refresh,
      ),
      child: CalendarQueuePattern(
        view: CalendarQueueView.queue,
        onViewChanged: (_) {},
        toolbarStart: const AppSectionHeader(
          title: "Today's queue",
          description: 'Front-desk flow for check-in and session start.',
        ),
        toolbarEnd: AppButton(
          label: 'Refresh',
          variant: AppButtonVariant.secondary,
          size: AppButtonSize.sm,
          leadingIcon: LucideIcons.refreshCw,
          onPressed: controller.refresh,
        ),
        queueHeader: AppointmentQueueStatsBanner(
          stats: stats,
          trendsUnavailable: state.comparisonUnavailable,
        ),
        queueColumns: buildAppointmentQueueColumns(
          context: context,
          items: state.items,
          branchLabel: branchLabel,
          shiftLookup: shiftLookupAsync.value ?? AppointmentQueueShiftDoctorLookup.empty,
          now: _now,
        ),
      ),
    );
  }

  String _branchLabel(List<BranchListItem> branches, String? branchId) {
    if (branchId == null) {
      return 'Active branch';
    }
    for (final branch in branches) {
      if (branch.id == branchId) {
        return branch.name;
      }
    }
    return 'Active branch';
  }
}
