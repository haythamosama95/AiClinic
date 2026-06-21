import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_queue_display.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_queue_provider.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/queue/appointment_queue_schedule_column.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/queue/appointment_queue_session_column.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/queue/appointment_queue_stats_banner.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/queue/appointment_queue_waiting_column.dart';

/// Three-column clinic queue dashboard for front-desk flow management.
class AppointmentQueuePage extends ConsumerStatefulWidget {
  const AppointmentQueuePage({super.key});

  @override
  ConsumerState<AppointmentQueuePage> createState() => _AppointmentQueuePageState();
}

class _AppointmentQueuePageState extends ConsumerState<AppointmentQueuePage> {
  Timer? _clockTimer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _clockTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) {
        setState(() => _now = DateTime.now());
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
                const _QueueHeader(),
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
                      SpacingTokens.sm,
                      SpacingTokens.lg,
                      SpacingTokens.lg,
                    ),
                    child: _QueueBody(state: state, now: _now),
                  ),
                ),
              ],
            ),
    );
  }
}

class _QueueHeader extends StatelessWidget {
  const _QueueHeader();

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;

    return Padding(
      padding: const EdgeInsets.fromLTRB(SpacingTokens.lg, SpacingTokens.lg, SpacingTokens.lg, SpacingTokens.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Clinic queue management',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: SpacingTokens.xs),
          Text(
            "Today's patient flow — scheduled, waiting, and in session",
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colors.mutedForeground),
          ),
        ],
      ),
    );
  }
}

class _QueueBody extends StatelessWidget {
  const _QueueBody({required this.state, required this.now});

  final AppointmentQueueState state;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final stats = AppointmentQueueDisplay.computeStats(state.items, now: now);
    final partition = AppointmentQueueDisplay.partition(state.items, now: now);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 1100;

        final columns = isWide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(flex: 4, child: AppointmentQueueScheduleColumn(items: partition.schedule)),
                  const SizedBox(width: SpacingTokens.md),
                  Expanded(
                    flex: 4,
                    child: AppointmentQueueWaitingColumn(items: partition.waiting, now: now),
                  ),
                  const SizedBox(width: SpacingTokens.md),
                  Expanded(
                    flex: 3,
                    child: AppointmentQueueSessionColumn(
                      activeSession: partition.activeSession,
                      nextUp: partition.nextUp,
                      now: now,
                    ),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(height: 280, child: AppointmentQueueScheduleColumn(items: partition.schedule)),
                  const SizedBox(height: SpacingTokens.md),
                  SizedBox(
                    height: 280,
                    child: AppointmentQueueWaitingColumn(items: partition.waiting, now: now),
                  ),
                  const SizedBox(height: SpacingTokens.md),
                  SizedBox(
                    height: 320,
                    child: AppointmentQueueSessionColumn(
                      activeSession: partition.activeSession,
                      nextUp: partition.nextUp,
                      now: now,
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
