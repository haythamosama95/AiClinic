import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:ai_clinic/app/navigation/app_navigator.dart';
import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_queue_display.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_queue_shift_doctors.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/queue/appointment_queue_row_advance_button.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/queue/appointment_queue_status_badge.dart';

/// Column 1 — today's appointment schedule in a clean list layout.
class AppointmentQueueScheduleColumn extends StatelessWidget {
  const AppointmentQueueScheduleColumn({
    required this.items,
    required this.now,
    this.shiftLookup = AppointmentQueueShiftDoctorLookup.empty,
    super.key,
  });

  final List<AppointmentListItem> items;
  final DateTime now;
  final AppointmentQueueShiftDoctorLookup shiftLookup;

  static final _timeFormat = DateFormat('hh:mm a');
  static final _dateFormat = DateFormat('MMM d, yyyy');

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
          _AppointmentsHeader(
            dateLabel: _dateFormat.format(now.toLocal()),
            onOpenCalendar: () => AppNavigator(context).goAppointmentsCalendar(),
          ),
          const Divider(height: 1),
          Expanded(
            child: items.isEmpty
                ? const _ScheduleEmptyState()
                : ListView.separated(
                    padding: EdgeInsets.zero,
                    itemCount: items.length,
                    separatorBuilder: (_, _) => Divider(height: 1, color: colors.border),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      final dimmed = AppointmentQueueDisplay.isScheduleRowDimmed(item);
                      return _AppointmentRow(
                        key: ValueKey(item.id),
                        item: item,
                        shiftLookup: shiftLookup,
                        siblingAppointments: items,
                        timeLabel: _timeFormat.format(item.startTime.toLocal()),
                        dimmed: dimmed,
                        now: now,
                        onTap: () => AppNavigator(context).pushAppointmentDetail(item.id, preview: item),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _AppointmentsHeader extends StatelessWidget {
  const _AppointmentsHeader({required this.dateLabel, required this.onOpenCalendar});

  final String dateLabel;
  final VoidCallback onOpenCalendar;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;

    return Padding(
      padding: const EdgeInsets.fromLTRB(SpacingTokens.lg, SpacingTokens.md, SpacingTokens.md, SpacingTokens.md),
      child: Row(
        children: [
          Text('Appointments', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const Spacer(),
          Text(dateLabel, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colors.mutedForeground)),
          const SizedBox(width: SpacingTokens.xs),
          _HeaderIconButton(icon: Icons.chevron_left, tooltip: 'Previous day', onPressed: onOpenCalendar),
          _HeaderIconButton(icon: Icons.chevron_right, tooltip: 'Next day', onPressed: onOpenCalendar),
          _HeaderIconButton(
            icon: Icons.calendar_today_outlined,
            tooltip: 'Open calendar',
            iconColor: colors.primary,
            onPressed: onOpenCalendar,
          ),
        ],
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({required this.icon, required this.tooltip, required this.onPressed, this.iconColor});

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;

    return IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      onPressed: onPressed,
      icon: Icon(icon, size: 20, color: iconColor ?? colors.mutedForeground),
    );
  }
}

class _AppointmentRow extends StatelessWidget {
  const _AppointmentRow({
    required this.item,
    required this.shiftLookup,
    required this.siblingAppointments,
    required this.timeLabel,
    required this.dimmed,
    required this.now,
    required this.onTap,
    super.key,
  });

  final AppointmentListItem item;
  final AppointmentQueueShiftDoctorLookup shiftLookup;
  final List<AppointmentListItem> siblingAppointments;
  final String timeLabel;
  final bool dimmed;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final opacity = dimmed ? 0.45 : 1.0;
    final showWait = item.status == AppointmentStatus.checkedIn;
    final waitLabel = showWait
        ? AppointmentQueueDisplay.formatWaitedLabel(AppointmentQueueDisplay.estimateWaitDuration(item, now: now))
        : null;

    final doctorPresentation = AppointmentQueueDisplay.queueDoctorPresentation(item, shiftLookup: shiftLookup);
    final visitLabel = _doctorVisitLabel(item);

    return Opacity(
      opacity: opacity,
      child: Material(
        color: colors.card,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.lg, vertical: SpacingTokens.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 76,
                  child: Text(
                    timeLabel,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: _PersonColumn(name: item.patientName, subtitle: item.type.label),
                ),
                const SizedBox(width: SpacingTokens.md),
                Expanded(
                  flex: 3,
                  child: _QueueDoctorColumn(
                    presentation: doctorPresentation,
                    visitLabel: visitLabel,
                    leadingTint: colors.primary.withValues(alpha: 0.12),
                  ),
                ),
                const SizedBox(width: SpacingTokens.sm),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppointmentQueueStatusBadge(status: item.status),
                    if (waitLabel != null) ...[
                      const SizedBox(height: SpacingTokens.xs / 2),
                      Text(
                        waitLabel,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: const Color(0xFF0891B2),
                          fontWeight: FontWeight.w600,
                          fontSize: 10,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
                AppointmentQueueRowAdvanceButton(item: item, siblingAppointments: siblingAppointments),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _doctorVisitLabel(AppointmentListItem item) {
    return switch (item.status) {
      AppointmentStatus.inProgress => 'In consultation',
      AppointmentStatus.completed => 'Completed visit',
      _ => 'Consultation',
    };
  }
}

class _QueueDoctorColumn extends StatelessWidget {
  const _QueueDoctorColumn({required this.presentation, required this.visitLabel, required this.leadingTint});

  final QueueAppointmentDoctorPresentation presentation;
  final String visitLabel;
  final Color leadingTint;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final names = presentation.displayNames;
    final subtitle = presentation.hasPatientChoice
        ? "Patient's choice · $visitLabel"
        : presentation.entries.length > 1
        ? 'On shift · $visitLabel'
        : visitLabel;

    return Row(
      children: [
        _PersonAvatar(name: presentation.avatarName, tint: leadingTint),
        const SizedBox(width: SpacingTokens.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (presentation.hasPatientChoice) ...[
                    Icon(Icons.star_rounded, size: 16, color: colors.primary),
                    const SizedBox(width: SpacingTokens.xs / 2),
                  ],
                  Expanded(
                    child: Text(
                      names,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.mutedForeground),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PersonColumn extends StatelessWidget {
  const _PersonColumn({required this.name, required this.subtitle, this.leading});

  final String name;
  final String subtitle;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;

    return Row(
      children: [
        leading ?? _PersonAvatar(name: name),
        const SizedBox(width: SpacingTokens.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.mutedForeground),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PersonAvatar extends StatelessWidget {
  const _PersonAvatar({required this.name, this.tint});

  final String name;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final background = tint ?? colors.secondary;

    return CircleAvatar(
      radius: 18,
      backgroundColor: background,
      child: Text(
        _initialsFor(name),
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: colors.foreground, fontWeight: FontWeight.w700, fontSize: 11),
      ),
    );
  }

  static String _initialsFor(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((part) => part.isNotEmpty).toList();
    if (parts.isEmpty) {
      return '?';
    }
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'.toUpperCase();
  }
}

class _ScheduleEmptyState extends StatelessWidget {
  const _ScheduleEmptyState();

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(SpacingTokens.lg),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.event_note_outlined, size: 40, color: colors.mutedForeground),
            const SizedBox(height: SpacingTokens.md),
            Text(
              'No appointments today',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: SpacingTokens.xs),
            Text(
              'Booked visits will appear here in time order.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.mutedForeground),
            ),
          ],
        ),
      ),
    );
  }
}
