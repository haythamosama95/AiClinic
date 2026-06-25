import 'package:flutter/material.dart';

import 'package:ai_clinic/app/navigation/app_navigator.dart';
import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_queue_display.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_queue_shift_doctors.dart';

/// Column 3 — active session cards (one per doctor) and next-up preview.
class AppointmentQueueSessionColumn extends StatelessWidget {
  const AppointmentQueueSessionColumn({
    required this.activeSessions,
    required this.nextUp,
    required this.now,
    this.shiftLookup = AppointmentQueueShiftDoctorLookup.empty,
    super.key,
  });

  final List<AppointmentListItem> activeSessions;
  final AppointmentListItem? nextUp;
  final DateTime now;
  final AppointmentQueueShiftDoctorLookup shiftLookup;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(SpacingTokens.lg),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(SpacingTokens.md, SpacingTokens.md, SpacingTokens.md, SpacingTokens.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Active sessions',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: SpacingTokens.xs / 2),
                Text(
                  activeSessions.length <= 1
                      ? 'Who is currently with the doctor'
                      : 'Patients currently in consultation by doctor',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.mutedForeground),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(SpacingTokens.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: activeSessions.isEmpty
                        ? const _NoActiveSessionPlaceholder()
                        : activeSessions.length == 1
                        ? _ActiveSessionHeroCard(item: activeSessions.first, now: now, shiftLookup: shiftLookup)
                        : ListView.separated(
                            itemCount: activeSessions.length,
                            separatorBuilder: (_, _) => const SizedBox(height: SpacingTokens.sm),
                            itemBuilder: (context, index) {
                              return _ActiveSessionCompactCard(
                                item: activeSessions[index],
                                now: now,
                                shiftLookup: shiftLookup,
                              );
                            },
                          ),
                  ),
                  if (nextUp != null) ...[
                    const SizedBox(height: SpacingTokens.md),
                    _NextUpPreview(item: nextUp!, shiftLookup: shiftLookup),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActiveSessionHeroCard extends StatelessWidget {
  const _ActiveSessionHeroCard({required this.item, required this.now, required this.shiftLookup});

  final AppointmentListItem item;
  final DateTime now;
  final AppointmentQueueShiftDoctorLookup shiftLookup;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final sessionLabel = AppointmentQueueDisplay.formatSessionLabel(
      AppointmentQueueDisplay.estimateSessionDuration(item, now: now),
    );
    final doctorLabel = AppointmentQueueDisplay.queueDoctorLabel(item, shiftLookup: shiftLookup);

    return Material(
      color: colors.primary.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(SpacingTokens.lg),
      child: InkWell(
        onTap: () => AppNavigator(context).pushAppointmentDetail(item.id, preview: item),
        borderRadius: BorderRadius.circular(SpacingTokens.lg),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(SpacingTokens.lg),
            border: Border.all(color: colors.primary.withValues(alpha: 0.35), width: 2),
          ),
          padding: const EdgeInsets.all(SpacingTokens.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'CURRENTLY WITH DOCTOR',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: colors.primary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
              const Spacer(),
              Text(
                item.patientName,
                style: Theme.of(
                  context,
                ).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w800, color: colors.foreground, height: 1.05),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: SpacingTokens.md),
              Row(
                children: [
                  Icon(Icons.timer_outlined, size: 18, color: colors.primary),
                  const SizedBox(width: SpacingTokens.xs),
                  Text(
                    sessionLabel,
                    style: Theme.of(
                      context,
                    ).textTheme.titleMedium?.copyWith(color: colors.primary, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: SpacingTokens.sm),
              Row(
                children: [
                  Icon(Icons.medical_services_outlined, size: 18, color: colors.mutedForeground),
                  const SizedBox(width: SpacingTokens.xs),
                  Expanded(
                    child: Text(
                      doctorLabel,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: colors.mutedForeground),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActiveSessionCompactCard extends StatelessWidget {
  const _ActiveSessionCompactCard({required this.item, required this.now, required this.shiftLookup});

  final AppointmentListItem item;
  final DateTime now;
  final AppointmentQueueShiftDoctorLookup shiftLookup;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final sessionLabel = AppointmentQueueDisplay.formatSessionLabel(
      AppointmentQueueDisplay.estimateSessionDuration(item, now: now),
    );
    final doctorLabel = AppointmentQueueDisplay.queueDoctorLabel(item, shiftLookup: shiftLookup);

    return Material(
      color: colors.primary.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(SpacingTokens.md),
      child: InkWell(
        onTap: () => AppNavigator(context).pushAppointmentDetail(item.id, preview: item),
        borderRadius: BorderRadius.circular(SpacingTokens.md),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(SpacingTokens.md),
            border: Border.all(color: colors.primary.withValues(alpha: 0.35)),
          ),
          padding: const EdgeInsets.all(SpacingTokens.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                doctorLabel,
                style: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(color: colors.primary, fontWeight: FontWeight.w700),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: SpacingTokens.xs),
              Text(
                item.patientName,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: SpacingTokens.xs),
              Row(
                children: [
                  Icon(Icons.timer_outlined, size: 16, color: colors.primary),
                  const SizedBox(width: SpacingTokens.xs),
                  Text(
                    sessionLabel,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: colors.primary, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoActiveSessionPlaceholder extends StatelessWidget {
  const _NoActiveSessionPlaceholder();

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.muted.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(SpacingTokens.lg),
        border: Border.all(color: colors.border, style: BorderStyle.solid),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(SpacingTokens.lg),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.meeting_room_outlined, size: 48, color: colors.mutedForeground),
              const SizedBox(height: SpacingTokens.md),
              Text(
                'No active sessions',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: SpacingTokens.sm),
              Text(
                'Use Call next on a waiting patient or advance status to start a session.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.mutedForeground),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NextUpPreview extends StatelessWidget {
  const _NextUpPreview({required this.item, required this.shiftLookup});

  final AppointmentListItem item;
  final AppointmentQueueShiftDoctorLookup shiftLookup;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final doctorLabel = AppointmentQueueDisplay.queueDoctorLabel(item, shiftLookup: shiftLookup);

    return Material(
      color: colors.background,
      borderRadius: BorderRadius.circular(SpacingTokens.md),
      child: InkWell(
        onTap: () => AppNavigator(context).pushAppointmentDetail(item.id, preview: item),
        borderRadius: BorderRadius.circular(SpacingTokens.md),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(SpacingTokens.md),
            border: Border.all(color: colors.border),
          ),
          padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.md, vertical: SpacingTokens.sm),
          child: Row(
            children: [
              Icon(Icons.skip_next_outlined, size: 20, color: colors.primary),
              const SizedBox(width: SpacingTokens.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Next up',
                      style: Theme.of(
                        context,
                      ).textTheme.labelSmall?.copyWith(color: colors.mutedForeground, fontWeight: FontWeight.w600),
                    ),
                    Text(
                      item.patientName,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Text(doctorLabel, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.mutedForeground)),
            ],
          ),
        ),
      ),
    );
  }
}
