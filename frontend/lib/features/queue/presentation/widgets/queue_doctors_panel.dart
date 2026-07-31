import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/components/app_progress.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/queue/domain/queue_display.dart';
import 'package:ai_clinic/features/queue/domain/queue_shift_doctors.dart';
import 'package:ai_clinic/features/queue/presentation/widgets/queue_secretary_utils.dart';

enum _DoctorQueueStatus { available, withPatient }

/// Doctors on shift with availability derived from in-progress assignments
/// (web `DoctorsPanel`).
class QueueDoctorsPanel extends StatelessWidget {
  const QueueDoctorsPanel({
    required this.doctors,
    required this.appointments,
    required this.now,
    this.embedded = false,
    super.key,
  });

  final List<QueueShiftDoctor> doctors;
  final List<AppointmentListItem> appointments;
  final DateTime now;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Semantics(
      container: true,
      label: 'Doctors on shift panel',
      child: DecoratedBox(
        decoration: embedded
            ? const BoxDecoration()
            : BoxDecoration(
                color: colors.surfaceDefault,
                borderRadius: BorderRadius.circular(AppRadius.xl),
                border: Border.all(color: colors.borderDefault),
              ),
        child: Column(
          mainAxisSize: embedded ? MainAxisSize.min : MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DecoratedBox(
              decoration: embedded
                  ? const BoxDecoration()
                  : BoxDecoration(
                      border: Border(bottom: BorderSide(color: colors.borderDefault)),
                    ),
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(
                  AppSpacing.space4,
                  AppSpacing.space3,
                  AppSpacing.space4,
                  AppSpacing.space3,
                ),
                child: Column(
                  crossAxisAlignment: embedded ? CrossAxisAlignment.center : CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Doctors on shift',
                      textAlign: embedded ? TextAlign.center : null,
                      style: AppTypography.bodySm(
                        context,
                      ).copyWith(fontWeight: FontWeight.w600, color: colors.textPrimary),
                    ),
                    Text(
                      '${doctors.length} providers today',
                      textAlign: embedded ? TextAlign.center : null,
                      style: AppTypography.caption(context).copyWith(color: colors.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
            if (embedded)
              ConstrainedBox(constraints: const BoxConstraints(maxHeight: 448), child: _buildDoctorList(colors))
            else
              Flexible(
                child: ConstrainedBox(constraints: const BoxConstraints(), child: _buildDoctorList(colors)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDoctorList(AppSemanticColors colors) {
    return ListView.separated(
      shrinkWrap: embedded,
      physics: embedded ? const ClampingScrollPhysics() : null,
      padding: const EdgeInsets.only(bottom: AppSpacing.space4),
      itemCount: doctors.length,
      separatorBuilder: (_, _) => Divider(height: 1, color: colors.borderSubtle),
      itemBuilder: (context, index) {
        return _DoctorRow(doctor: doctors[index], appointments: appointments, now: now);
      },
    );
  }
}

class _DoctorRow extends StatelessWidget {
  const _DoctorRow({required this.doctor, required this.appointments, required this.now});

  final QueueShiftDoctor doctor;
  final List<AppointmentListItem> appointments;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final inProgress = AppointmentQueueDisplay.inProgressAppointmentForDoctor(doctor.id, appointments);
    final status = inProgress == null ? _DoctorQueueStatus.available : _DoctorQueueStatus.withPatient;
    final patientsSeenToday = appointments
        .where((item) => item.doctorId == doctor.id && item.status == AppointmentStatus.completed)
        .length;
    final lag = queueDoctorLagMinutes(doctor, appointments, now: now);
    final idle = status == _DoctorQueueStatus.available ? queueDoctorIdleMinutes(doctor, appointments, now: now) : 0;

    final badgeBackground = switch (status) {
      _DoctorQueueStatus.available => colors.statusSuccessSurface,
      _DoctorQueueStatus.withPatient => colors.statusInfoSurface,
    };
    final badgeForeground = switch (status) {
      _DoctorQueueStatus.available => colors.statusSuccessFg,
      _DoctorQueueStatus.withPatient => colors.statusInfoFg,
    };
    final badgeLabel = switch (status) {
      _DoctorQueueStatus.available => 'Available',
      _DoctorQueueStatus.withPatient => 'With patient',
    };
    final badgeIcon = switch (status) {
      _DoctorQueueStatus.available => Icons.verified_user_outlined,
      _DoctorQueueStatus.withPatient => Icons.medical_services_outlined,
    };

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSpacing.space4,
        AppSpacing.space3,
        AppSpacing.space4,
        AppSpacing.space3,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  doctor.name,
                  style: AppTypography.bodySm(context).copyWith(fontWeight: FontWeight.w500, color: colors.textPrimary),
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(color: badgeBackground, borderRadius: BorderRadius.circular(AppRadius.full)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space2, vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(badgeIcon, size: 12, color: badgeForeground),
                      const SizedBox(width: 4),
                      Text(
                        badgeLabel,
                        style: AppTypography.caption(context).copyWith(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                          color: badgeForeground,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (inProgress != null) ...[
            const SizedBox(height: AppSpacing.space2),
            Text.rich(
              TextSpan(
                text: 'With ',
                style: AppTypography.caption(context).copyWith(color: colors.textSecondary),
                children: [
                  TextSpan(
                    text: inProgress.patientName,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.space2),
          Wrap(
            spacing: AppSpacing.space2,
            runSpacing: AppSpacing.space1,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '$patientsSeenToday seen today',
                style: AppTypography.caption(context).copyWith(color: colors.textSecondary),
              ),
              if (status == _DoctorQueueStatus.available && idle > 0)
                Text(
                  'Idle ${AppointmentQueueDisplay.formatDurationLabel(Duration(minutes: idle))}',
                  style: AppTypography.mono(context).copyWith(fontSize: 12, color: colors.statusSuccessFg),
                ),
              if (lag >= 15)
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.statusWarningSurface,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Text(
                      '+$lag min behind',
                      style: AppTypography.caption(context).copyWith(
                        fontWeight: FontWeight.w500,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: colors.statusWarningFg,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.space2),
          AppProgress(value: (patientsSeenToday * 12).clamp(0, 100).toDouble(), size: ProgressSize.sm),
        ],
      ),
    );
  }
}
