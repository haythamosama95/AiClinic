import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

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
import 'package:ai_clinic/features/appointments/presentation/widgets/queue/appointment_queue_row_tokens.dart';

/// Column 3 — doctors on the current shift.
class AppointmentQueueSessionColumn extends StatelessWidget {
  const AppointmentQueueSessionColumn({
    required this.appointments,
    required this.now,
    this.shiftLookup = AppointmentQueueShiftDoctorLookup.empty,
    this.doctorsLoading = false,
    this.onDoctorTap,
    this.bodyScrollable = true,
    super.key,
  });

  final List<AppointmentListItem> appointments;
  final DateTime now;
  final AppointmentQueueShiftDoctorLookup shiftLookup;
  final bool doctorsLoading;
  final ValueChanged<AppointmentListItem>? onDoctorTap;

  /// When false, the list expands to show every row and defers scrolling to the page.
  final bool bodyScrollable;

  @override
  Widget build(BuildContext context) {
    final doctorsOnShift = shiftLookup.doctorsOnCurrentShiftAt(now);
    final onShiftCount = doctorsOnShift.length;

    return AppNotchedCard(
      titleIcon: Icons.medical_services_outlined,
      title: Text('Doctors', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
      actions: [
        AppNotchedCardAction(
          providesOwnBackground: true,
          action: AppBadge(
            label: doctorsLoading ? 'Loading…' : _onShiftCountLabel(onShiftCount),
            icon: const Icon(Icons.medical_services_outlined),
            variant: doctorsLoading || onShiftCount == 0 ? AppBadgeVariant.muted : AppBadgeVariant.outline,
            comfortable: true,
          ),
        ),
      ],
      body: doctorsLoading
          ? const Center(child: CircularProgressIndicator())
          : doctorsOnShift.isEmpty
          ? const AppointmentQueuePanelEmptyState(
              icon: Icons.medical_services_outlined,
              title: 'No doctors on shift',
              message: 'Assign doctors to an active shift for this branch.',
            )
          : ListView.separated(
              shrinkWrap: !bodyScrollable,
              physics: bodyScrollable ? null : const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.all(SpacingTokens.md),
              itemCount: doctorsOnShift.length,
              separatorBuilder: (_, _) => const SizedBox(height: SpacingTokens.sm),
              itemBuilder: (context, index) {
                final doctor = doctorsOnShift[index];
                final inProgressAppointment = AppointmentQueueDisplay.inProgressAppointmentForDoctor(
                  doctor.id,
                  appointments,
                );
                return _DoctorOnShiftRow(
                  doctor: doctor,
                  inProgressAppointment: inProgressAppointment,
                  now: now,
                  onTap: inProgressAppointment != null && onDoctorTap != null
                      ? () => onDoctorTap!(inProgressAppointment)
                      : null,
                );
              },
            ),
    );
  }

  static String _onShiftCountLabel(int count) {
    return switch (count) {
      0 => 'None on shift',
      1 => '1 on shift',
      _ => '$count on shift',
    };
  }
}

class _DoctorOnShiftRow extends StatelessWidget {
  const _DoctorOnShiftRow({required this.doctor, required this.now, this.inProgressAppointment, this.onTap});

  final QueueShiftDoctor doctor;
  final DateTime now;
  final AppointmentListItem? inProgressAppointment;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final textTheme = Theme.of(context).textTheme;
    final hasPatientInProgress = inProgressAppointment != null;
    final statusColor = hasPatientInProgress
        ? AppointmentCalendarDisplay.statusColor(AppointmentStatus.inProgress)
        : AppointmentCalendarDisplay.statusColor(AppointmentStatus.scheduled);
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
                        icon: Icons.medical_services_outlined,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AppointmentScaleDownText(
                              text: doctor.name,
                              style: textTheme.bodyMedium?.copyWith(
                                color: colors.foreground,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'On shift',
                              style: textTheme.bodySmall?.copyWith(color: colors.mutedForeground),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ),
                    AppointmentQueueSectionDivider(color: colors.border),
                    Expanded(
                      flex: 3,
                      child: TiltedBackgroundIconStack(
                        icon: Icons.assignment_ind_outlined,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AppointmentScaleDownText(
                              text: hasPatientInProgress
                                  ? inProgressAppointment!.patientName
                                  : 'No patient in progress',
                              style: textTheme.bodyMedium?.copyWith(
                                color: hasPatientInProgress ? colors.foreground : colors.mutedForeground,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              hasPatientInProgress
                                  ? AppointmentQueueDisplay.formatSessionLabel(
                                      AppointmentQueueDisplay.estimateSessionDuration(inProgressAppointment!, now: now),
                                    )
                                  : 'Available',
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
