import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:intl/intl.dart';

import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/shape_tokens.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_calendar_display.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_queue_display.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_queue_shift_doctors.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_scale_down_text.dart';

/// Checked-in patients waiting to be seen, sorted by appointment time.
class AppointmentQueueWaitingColumn extends StatelessWidget {
  const AppointmentQueueWaitingColumn({
    required this.items,
    required this.now,
    this.shiftLookup = AppointmentQueueShiftDoctorLookup.empty,
    this.onPatientTap,
    super.key,
  });

  final List<AppointmentListItem> items;
  final DateTime now;
  final AppointmentQueueShiftDoctorLookup shiftLookup;
  final ValueChanged<AppointmentListItem>? onPatientTap;

  static final _timeFormat = DateFormat('h:mm a');

  @override
  Widget build(BuildContext context) {
    final waitingCount = items.length;

    return AppNotchedCard(
      titleIcon: Icons.how_to_reg_outlined,
      title: Text('Checked in', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
      actions: [
        AppNotchedCardAction(
          providesOwnBackground: true,
          action: AppBadge(
            label: _waitingCountLabel(waitingCount),
            icon: const Icon(Icons.people_outline),
            variant: waitingCount == 0 ? AppBadgeVariant.muted : AppBadgeVariant.outline,
            comfortable: true,
          ),
        ),
      ],
      body: items.isEmpty
          ? const Padding(padding: EdgeInsets.all(SpacingTokens.md), child: _NoCheckedInPlaceholder())
          : ListView.separated(
              padding: const EdgeInsets.all(SpacingTokens.md),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: SpacingTokens.sm),
              itemBuilder: (context, index) {
                final item = items[index];
                return _CheckedInPatientRow(
                  item: item,
                  preferredDoctorLabel: _preferredDoctorLabel(item),
                  timeLabel: _timeFormat.format(item.startTime.toLocal()),
                  waitLabel: AppointmentQueueDisplay.formatWaitedLabel(
                    AppointmentQueueDisplay.estimateWaitDuration(item, now: now),
                  ),
                  onTap: onPatientTap == null ? null : () => onPatientTap!(item),
                );
              },
            ),
    );
  }

  String _preferredDoctorLabel(AppointmentListItem item) {
    final presentation = AppointmentQueueDisplay.queueDoctorPresentation(item, shiftLookup: shiftLookup);
    if (presentation.displayNames == AppointmentQueueDisplay.noPreferredDoctorLabel) {
      return AppointmentQueueDisplay.noPreferredDoctorLabel;
    }
    if (presentation.hasPatientChoice) {
      return "Patient's choice · ${presentation.displayNames}";
    }
    return presentation.displayNames;
  }

  static String _waitingCountLabel(int count) {
    return switch (count) {
      0 => 'None waiting',
      1 => '1 waiting',
      _ => '$count waiting',
    };
  }
}

class _CheckedInPatientRow extends StatelessWidget {
  const _CheckedInPatientRow({
    required this.item,
    required this.preferredDoctorLabel,
    required this.timeLabel,
    required this.waitLabel,
    this.onTap,
  });

  final AppointmentListItem item;
  final String preferredDoctorLabel;
  final String timeLabel;
  final String waitLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final textTheme = Theme.of(context).textTheme;
    final statusColor = AppointmentCalendarDisplay.statusColor(AppointmentStatus.checkedIn);
    final borderRadius = BorderRadius.circular(context.shapeTokens.lg);

    return FCard.raw(
      style: FCardStyleDelta.delta(
        decoration: DecorationDelta.boxDelta(
          color: colors.card,
          border: Border.all(color: colors.border),
          borderRadius: borderRadius,
        ),
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Ink(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [statusColor.withValues(alpha: 0.22), statusColor.withValues(alpha: 0)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.lg, vertical: SpacingTokens.md),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 7,
                      child: TiltedBackgroundIconStack(
                        icon: Icons.assignment_ind_outlined,
                        minIconSize: 60,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AppointmentScaleDownText(
                              text: item.patientName,
                              style: textTheme.bodyMedium?.copyWith(
                                color: colors.foreground,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              preferredDoctorLabel,
                              style: textTheme.bodySmall?.copyWith(color: colors.mutedForeground),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ),
                    _QueueSectionDivider(color: colors.border),
                    Expanded(
                      flex: 3,
                      child: TiltedBackgroundIconStack(
                        icon: Icons.schedule_outlined,
                        minIconSize: 60,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              timeLabel,
                              style: textTheme.titleSmall?.copyWith(
                                color: colors.foreground,
                                fontWeight: FontWeight.w700,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              waitLabel,
                              style: textTheme.bodySmall?.copyWith(color: colors.mutedForeground),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _QueueSectionDivider extends StatelessWidget {
  const _QueueSectionDivider({required this.color});

  final Color color;

  static const _gap = SpacingTokens.md;
  static const _lineHeight = 40.0;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _gap * 2 + 1,
      child: Center(
        child: SizedBox(
          height: _lineHeight,
          child: VerticalDivider(width: 1, thickness: 1, color: color.withValues(alpha: 1)),
        ),
      ),
    );
  }
}

class _NoCheckedInPlaceholder extends StatelessWidget {
  const _NoCheckedInPlaceholder();

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
              Icon(Icons.how_to_reg_outlined, size: 48, color: colors.mutedForeground),
              const SizedBox(height: SpacingTokens.md),
              Text(
                'No patients checked in',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: SpacingTokens.sm),
              Text(
                'Checked-in patients will appear here in appointment order.',
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
