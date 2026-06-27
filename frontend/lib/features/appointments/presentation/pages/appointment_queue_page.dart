import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_queue_display.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_queue_shift_doctors.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_queue_provider.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_queue_shift_provider.dart';
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

        final columns = isWide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 3,
                    child: AppointmentQueueScheduleColumn(
                      items: partition.schedule,
                      now: now,
                      shiftLookup: shiftLookup,
                      scrollNonce: scrollNonce,
                      scrollToAppointmentId: scrollToAppointmentId,
                      onTargetAppointmentScrollHandled: onTargetAppointmentScrollHandled,
                    ),
                  ),
                  const SizedBox(width: SpacingTokens.md),
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: AppointmentQueueSessionColumn(
                            appointments: state.items,
                            now: now,
                            shiftLookup: shiftLookup,
                            doctorsLoading: doctorsLoading,
                          ),
                        ),
                        const SizedBox(height: SpacingTokens.md),
                        Expanded(
                          child: AppointmentQueueWaitingColumn(
                            items: partition.waiting,
                            now: now,
                            shiftLookup: shiftLookup,
                            onPatientTap: (item) => onCheckedInPatientTap(item.id),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 3,
                    child: AppointmentQueueScheduleColumn(
                      items: partition.schedule,
                      now: now,
                      shiftLookup: shiftLookup,
                      scrollNonce: scrollNonce,
                      scrollToAppointmentId: scrollToAppointmentId,
                      onTargetAppointmentScrollHandled: onTargetAppointmentScrollHandled,
                    ),
                  ),
                  const SizedBox(height: SpacingTokens.md),
                  Expanded(
                    flex: 2,
                    child: AppointmentQueueSessionColumn(
                      appointments: state.items,
                      now: now,
                      shiftLookup: shiftLookup,
                      doctorsLoading: doctorsLoading,
                    ),
                  ),
                  const SizedBox(height: SpacingTokens.md),
                  Expanded(
                    flex: 2,
                    child: AppointmentQueueWaitingColumn(
                      items: partition.waiting,
                      now: now,
                      shiftLookup: shiftLookup,
                      onPatientTap: (item) => onCheckedInPatientTap(item.id),
                    ),
                  ),
                ],
              );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppointmentQueueStatsBanner(stats: stats),
            const SizedBox(height: SpacingTokens.lg),
            Expanded(child: columns),
          ],
        );
      },
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
            Icon(Icons.lock_outline, size: 48, color: colors.mutedForeground),
            const SizedBox(height: SpacingTokens.md),
            Text('Queue access required', style: Theme.of(context).textTheme.titleLarge),
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
