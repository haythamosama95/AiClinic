import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_queue_display.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_org_calendar.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_queue_shift_doctors.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_queue_provider.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_queue_shift_provider.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/queue/appointment_queue_row_tokens.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/queue/appointment_queue_schedule_column.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/queue/appointment_queue_session_column.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/queue/appointment_queue_stats_banner.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/queue/appointment_queue_waiting_column.dart';

/// Clinic queue dashboard for front-desk flow management.
class AppointmentQueuePage extends ConsumerStatefulWidget {
  const AppointmentQueuePage({super.key});

  @override
  ConsumerState<AppointmentQueuePage> createState() => _AppointmentQueuePageState();
}

class _AppointmentQueuePageState extends ConsumerState<AppointmentQueuePage> {
  Timer? _clockTimer;
  DateTime _now = DateTime.now();
  int _scheduleScrollNonce = 0;
  String? _scrollToAppointmentId;
  bool _routeScrollPrimed = false;
  bool _wasCurrentRoute = false;

  @override
  void initState() {
    super.initState();
    _bumpScheduleScroll();
    _clockTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) {
        setState(() => _now = DateTime.now());
      }
    });
  }

  void _bumpScheduleScroll() {
    _scheduleScrollNonce = DateTime.now().millisecondsSinceEpoch;
  }

  void _onCheckedInPatientTap(String appointmentId) {
    setState(() {
      _scrollToAppointmentId = appointmentId;
      _bumpScheduleScroll();
    });
  }

  void _onTargetAppointmentScrollHandled() {
    if (_scrollToAppointmentId == null) {
      return;
    }
    setState(() => _scrollToAppointmentId = null);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final isCurrent = ModalRoute.of(context)?.isCurrent ?? false;
    if (isCurrent && !_wasCurrentRoute) {
      if (_routeScrollPrimed) {
        setState(_bumpScheduleScroll);
      } else {
        _routeScrollPrimed = true;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        unawaited(ref.read(appointmentQueueProvider.notifier).refresh());
      });
      _wasCurrentRoute = true;
    } else if (!isCurrent) {
      _wasCurrentRoute = false;
    }
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final canAccess = ref.watch(permissionServiceProvider).canAccessAppointments();
    if (!canAccess) {
      return const _QueuePermissionDenied();
    }

    final state = ref.watch(appointmentQueueProvider);
    final controller = ref.read(appointmentQueueProvider.notifier);

    return Material(
      color: colors.background,
      child: state.loading && state.items.isEmpty
          ? const Center(child: AppSkeletonBox(height: 320))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (state.error != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(SpacingTokens.lg, 0, SpacingTokens.lg, SpacingTokens.sm),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(state.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                        const SizedBox(height: SpacingTokens.sm),
                        AppButton(label: 'Retry', variant: AppButtonVariant.secondary, onPressed: controller.refresh),
                      ],
                    ),
                  ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      SpacingTokens.lg,
                      SpacingTokens.lg,
                      SpacingTokens.lg,
                      SpacingTokens.lg,
                    ),
                    child: _QueueBody(
                      state: state,
                      now: _now,
                      scrollNonce: _scheduleScrollNonce,
                      scrollToAppointmentId: _scrollToAppointmentId,
                      onCheckedInPatientTap: _onCheckedInPatientTap,
                      onTargetAppointmentScrollHandled: _onTargetAppointmentScrollHandled,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

/// Minimum notched-card heights when the queue fills the viewport (wide layout).
typedef _QueuePanelHeights = AppointmentQueuePanelHeights;

/// Below this viewport height the page scrolls and column lists expand (shrink-wrap).
const _minViewportHeightForColumnScrolling = 560.0;

class _QueueBody extends ConsumerWidget {
  const _QueueBody({
    required this.state,
    required this.now,
    required this.scrollNonce,
    required this.scrollToAppointmentId,
    required this.onCheckedInPatientTap,
    required this.onTargetAppointmentScrollHandled,
  });

  final AppointmentQueueState state;
  final DateTime now;
  final int scrollNonce;
  final String? scrollToAppointmentId;
  final ValueChanged<String> onCheckedInPatientTap;
  final VoidCallback onTargetAppointmentScrollHandled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shiftLookupAsync = ref.watch(appointmentQueueShiftDoctorLookupProvider);
    final organizationTimezone = effectiveOrganizationTimezone(
      ref.watch(authSessionProvider).context?.organizationTimezone,
    );
    final shiftLookup = shiftLookupAsync.value ?? AppointmentQueueShiftDoctorLookup.empty;
    final doctorsLoading = shiftLookupAsync.isLoading && !shiftLookupAsync.hasValue;
    final stats = AppointmentQueueDisplay.computeStats(
      state.items,
      now: now,
      comparisonItems: state.comparisonItems,
      comparisonNow: state.comparisonNow,
    );
    final partition = AppointmentQueueDisplay.partition(state.items, now: now);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 1100;
        final statsHeightEstimate = constraints.maxWidth < 720
            ? _QueuePanelHeights.statsBannerCompact
            : _QueuePanelHeights.statsBannerWide;
        final minColumnsHeight = _minColumnsHeight(isWide);
        final minBodyHeight = statsHeightEstimate + SpacingTokens.lg + minColumnsHeight;
        final fillsViewport =
            constraints.maxHeight >= minBodyHeight && constraints.maxHeight >= _minViewportHeightForColumnScrolling;

        final scheduleColumn = AppointmentQueueScheduleColumn(
          items: partition.schedule,
          now: now,
          shiftLookup: shiftLookup,
          scrollNonce: scrollNonce,
          scrollToAppointmentId: scrollToAppointmentId,
          onTargetAppointmentScrollHandled: onTargetAppointmentScrollHandled,
          bodyScrollable: fillsViewport,
        );
        final sessionColumn = AppointmentQueueSessionColumn(
          appointments: state.items,
          now: now,
          shiftLookup: shiftLookup,
          doctorsLoading: doctorsLoading,
          onDoctorTap: (item) => onCheckedInPatientTap(item.id),
          bodyScrollable: fillsViewport,
        );
        final waitingColumn = AppointmentQueueWaitingColumn(
          items: partition.waiting,
          now: now,
          shiftLookup: shiftLookup,
          organizationTimezone: organizationTimezone,
          onPatientTap: (item) => onCheckedInPatientTap(item.id),
          bodyScrollable: fillsViewport,
        );

        final columns = isWide
            ? _buildWideColumns(
                fillsViewport: fillsViewport,
                scheduleColumn: scheduleColumn,
                sessionColumn: sessionColumn,
                waitingColumn: waitingColumn,
              )
            : _buildNarrowColumns(
                fillsViewport: fillsViewport,
                scheduleColumn: scheduleColumn,
                sessionColumn: sessionColumn,
                waitingColumn: waitingColumn,
              );

        final body = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppointmentQueueStatsBanner(stats: stats, trendsUnavailable: state.comparisonUnavailable),
            const SizedBox(height: SpacingTokens.lg),
            if (fillsViewport) Expanded(child: columns) else columns,
          ],
        );

        if (fillsViewport) {
          return body;
        }

        return SingleChildScrollView(child: body);
      },
    );
  }

  static double _minColumnsHeight(bool isWide) {
    final stackedSidePanels = _QueuePanelHeights.session + SpacingTokens.md + _QueuePanelHeights.waiting;

    if (isWide) {
      return math.max(_QueuePanelHeights.schedule, stackedSidePanels);
    }

    return _QueuePanelHeights.schedule + SpacingTokens.md + stackedSidePanels;
  }

  static Widget _queuePanel({
    required bool fillsViewport,
    required double minHeight,
    required Widget child,
    int flex = 1,
  }) {
    if (fillsViewport) {
      return Expanded(
        flex: flex,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: minHeight),
          child: child,
        ),
      );
    }

    return child;
  }

  /// Row children always need horizontal flex even when the page scrolls vertically.
  static Widget _wideRowPanel({
    required bool fillsViewport,
    required double minHeight,
    required Widget child,
    int flex = 1,
  }) {
    if (fillsViewport) {
      return Expanded(
        flex: flex,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: minHeight),
          child: child,
        ),
      );
    }

    return Expanded(flex: flex, child: child);
  }

  static Widget _buildWideColumns({
    required bool fillsViewport,
    required Widget scheduleColumn,
    required Widget sessionColumn,
    required Widget waitingColumn,
  }) {
    final sidePanels = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _queuePanel(fillsViewport: fillsViewport, minHeight: _QueuePanelHeights.session, flex: 2, child: sessionColumn),
        const SizedBox(height: SpacingTokens.md),
        _queuePanel(fillsViewport: fillsViewport, minHeight: _QueuePanelHeights.waiting, flex: 2, child: waitingColumn),
      ],
    );

    return Row(
      crossAxisAlignment: fillsViewport ? CrossAxisAlignment.stretch : CrossAxisAlignment.start,
      children: [
        _wideRowPanel(
          fillsViewport: fillsViewport,
          minHeight: _QueuePanelHeights.schedule,
          flex: 3,
          child: scheduleColumn,
        ),
        const SizedBox(width: SpacingTokens.md),
        Expanded(flex: 2, child: sidePanels),
      ],
    );
  }

  static Widget _buildNarrowColumns({
    required bool fillsViewport,
    required Widget scheduleColumn,
    required Widget sessionColumn,
    required Widget waitingColumn,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _queuePanel(
          fillsViewport: fillsViewport,
          minHeight: _QueuePanelHeights.schedule,
          flex: 3,
          child: scheduleColumn,
        ),
        const SizedBox(height: SpacingTokens.md),
        _queuePanel(fillsViewport: fillsViewport, minHeight: _QueuePanelHeights.session, flex: 2, child: sessionColumn),
        const SizedBox(height: SpacingTokens.md),
        _queuePanel(fillsViewport: fillsViewport, minHeight: _QueuePanelHeights.waiting, flex: 2, child: waitingColumn),
      ],
    );
  }
}

class _QueuePermissionDenied extends StatelessWidget {
  const _QueuePermissionDenied();

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(SpacingTokens.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 36, color: colors.mutedForeground),
            const SizedBox(height: SpacingTokens.md),
            Text('Queue access required', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: SpacingTokens.sm),
            Text(
              'You need appointment permissions to view the clinic queue.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colors.mutedForeground),
            ),
          ],
        ),
      ),
    );
  }
}
