import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/queue/domain/queue_display.dart';
import 'package:ai_clinic/features/queue/domain/queue_shift_doctors.dart';
import 'package:ai_clinic/features/queue/presentation/widgets/queue_flow_card.dart';
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
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 448),
                child: _buildDoctorList(context, colors),
              )
            else
              Flexible(
                child: ConstrainedBox(constraints: const BoxConstraints(), child: _buildDoctorList(context, colors)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDoctorList(BuildContext context, AppSemanticColors colors) {
    if (doctors.isEmpty) {
      return Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(
          AppSpacing.space3,
          AppSpacing.space2,
          AppSpacing.space3,
          AppSpacing.space3,
        ),
        child: Text(
          'No providers on shift',
          style: AppTypography.bodySm(context).copyWith(color: colors.textSecondary),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSpacing.space3,
        AppSpacing.space2,
        AppSpacing.space3,
        AppSpacing.space3,
      ),
      child: QueueFlowList(
        child: ListView.separated(
          shrinkWrap: embedded,
          physics: embedded ? const ClampingScrollPhysics() : null,
          padding: EdgeInsets.zero,
          itemCount: doctors.length,
          separatorBuilder: (_, _) => Divider(height: 1, thickness: 1, color: colors.borderDefault),
          itemBuilder: (context, index) {
            return _DoctorRow(doctor: doctors[index], appointments: appointments, now: now);
          },
        ),
      ),
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
    final inProgress = AppointmentQueueDisplay.inProgressAppointmentForDoctor(doctor.id, appointments);
    final status = inProgress == null ? _DoctorQueueStatus.available : _DoctorQueueStatus.withPatient;
    final patientsSeenToday = appointments
        .where((item) => item.doctorId == doctor.id && item.status == AppointmentStatus.completed)
        .length;
    final lag = queueDoctorLagMinutes(doctor, appointments, now: now);
    final idle = status == _DoctorQueueStatus.available ? queueDoctorIdleMinutes(doctor, appointments, now: now) : 0;

    return QueueDoctorShiftRow(
      doctorName: doctor.name,
      isAvailable: status == _DoctorQueueStatus.available,
      patientsSeenToday: patientsSeenToday,
      currentPatientName: inProgress?.patientName,
      idleLabel: status == _DoctorQueueStatus.available && idle > 0
          ? 'Idle ${AppointmentQueueDisplay.formatDurationLabel(Duration(minutes: idle))}'
          : null,
      lagMinutes: lag >= 15 ? lag : null,
    );
  }
}
