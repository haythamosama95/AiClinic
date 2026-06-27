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

/// Column 3 — doctors on the current shift.
class AppointmentQueueSessionColumn extends StatelessWidget {
  const AppointmentQueueSessionColumn({
    required this.appointments,
    required this.now,
    this.shiftLookup = AppointmentQueueShiftDoctorLookup.empty,
    this.doctorsLoading = false,
    this.onDoctorTap,
    super.key,
  });

  final List<AppointmentListItem> appointments;
  final DateTime now;
  final AppointmentQueueShiftDoctorLookup shiftLookup;
  final bool doctorsLoading;
  final ValueChanged<AppointmentListItem>? onDoctorTap;

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
          ? const Padding(padding: EdgeInsets.all(SpacingTokens.md), child: _NoDoctorsOnShiftPlaceholder())
          : ListView.separated(
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
                padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.lg, vertical: SpacingTokens.md),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TiltedBackgroundIconStack(
                        icon: Icons.medical_services_outlined,
                        minIconSize: 60,
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
                    _QueueSectionDivider(color: colors.border),
                    Expanded(
                      child: TiltedBackgroundIconStack(
                        icon: Icons.assignment_ind_outlined,
                        minIconSize: 60,
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

/// Centered vertical divider between queue card sections.
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

class _NoDoctorsOnShiftPlaceholder extends StatelessWidget {
  const _NoDoctorsOnShiftPlaceholder();

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
              Icon(Icons.medical_services_outlined, size: 48, color: colors.mutedForeground),
              const SizedBox(height: SpacingTokens.md),
              Text(
                'No doctors on shift',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: SpacingTokens.sm),
              Text(
                'Assign doctors to an active shift for this branch.',
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
