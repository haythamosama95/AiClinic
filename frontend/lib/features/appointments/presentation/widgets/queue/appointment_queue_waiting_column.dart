import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:intl/intl.dart';

import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/shape_tokens.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_calendar_display.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_org_calendar.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_queue_display.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_queue_shift_doctors.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_scale_down_text.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/queue/appointment_queue_row_tokens.dart';

/// Checked-in patients waiting to be seen, sorted by appointment time.
class AppointmentQueueWaitingColumn extends StatelessWidget {
  const AppointmentQueueWaitingColumn({
    required this.items,
    required this.now,
    this.shiftLookup = AppointmentQueueShiftDoctorLookup.empty,
    this.organizationTimezone = 'UTC',
    this.onPatientTap,
    this.bodyScrollable = true,
    super.key,
  });

  final List<AppointmentListItem> items;
  final DateTime now;
  final AppointmentQueueShiftDoctorLookup shiftLookup;
  final String organizationTimezone;
  final ValueChanged<AppointmentListItem>? onPatientTap;

  /// When false, the list expands to show every row and defers scrolling to the page.
  final bool bodyScrollable;

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
          ? const AppointmentQueuePanelEmptyState(
              icon: Icons.how_to_reg_outlined,
              title: 'No patients checked in',
              message: 'Checked-in patients will appear here in appointment order.',
            )
          : ListView.separated(
              shrinkWrap: !bodyScrollable,
              physics: bodyScrollable ? null : const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.all(SpacingTokens.md),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: SpacingTokens.sm),
              itemBuilder: (context, index) {
                final item = items[index];
                return _CheckedInPatientRow(
                  item: item,
                  preferredDoctorLabel: _preferredDoctorLabel(item),
                  timeLabel: _timeFormat.format(
                    appointmentWallClockInOrganizationTimezone(organizationTimezone, item.startTime),
                  ),
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
                padding: AppointmentQueueRowTokens.rowPadding,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: TiltedBackgroundIconStack(
                        icon: Icons.assignment_ind_outlined,
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
                    AppointmentQueueSectionDivider(color: colors.border),
                    SizedBox(
                      width: AppointmentQueueRowTokens.timeColumnWidth,
                      child: TiltedBackgroundIconStack(
                        icon: Icons.schedule_outlined,
                        minIconSize: AppointmentQueueRowTokens.timeIconMinSize,
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
