import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_type.dart';
import 'package:ai_clinic/features/patients/presentation/widgets/patient_branch_pill.dart';
import 'package:ai_clinic/features/patients/presentation/widgets/patient_date_stamp.dart';
import 'package:ai_clinic/features/patients/presentation/widgets/patient_record_card.dart';
import 'package:ai_clinic/features/visits/domain/visit_list_item.dart';
import 'package:ai_clinic/features/visits/domain/visit_status.dart';

/// Unified visit/appointment record card for the patient detail Visits tab.
class PatientVisitRecordCard extends StatelessWidget {
  const PatientVisitRecordCard._({
    required this.date,
    required this.doctorName,
    required this.badges,
    this.branchName,
    super.key,
  });

  factory PatientVisitRecordCard.fromVisit(VisitListItem visit, {Key? key}) {
    return PatientVisitRecordCard._(
      key: key,
      date: visit.visitDate,
      doctorName: visit.doctorName,
      badges: [
        (
          label: AppointmentType.planned.label,
          color: _appointmentTypeColor(AppointmentType.planned),
        ),
        (label: visit.status.label, color: _visitStatusColor(visit.status)),
      ],
      branchName: visit.branchName,
    );
  }

  factory PatientVisitRecordCard.fromAppointment(
    AppointmentListItem appointment, {
    String? branchName,
    Key? key,
  }) {
    final resolvedBranchName = branchName?.trim();

    return PatientVisitRecordCard._(
      key: key,
      date: appointment.startTime,
      doctorName: appointment.doctorDisplayName,
      badges: [
        (
          label: appointment.type.label,
          color: _appointmentTypeColor(appointment.type),
        ),
        (
          label: appointment.status.label,
          color: _appointmentStatusColor(appointment.status),
        ),
      ],
      branchName: resolvedBranchName?.isNotEmpty == true
          ? resolvedBranchName
          : null,
    );
  }

  final DateTime date;
  final String doctorName;
  final List<({String label, BadgeColor color})> badges;
  final String? branchName;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final resolvedBranchName = branchName?.trim();

    return PatientRecordCard(
      leading: PatientDateStamp(date: date),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.space5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              doctorName,
              style: AppTypography.bodyStrong(
                context,
              ).copyWith(color: colors.textPrimary),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: AppSpacing.space5),
            Wrap(
              spacing: AppSpacing.space2,
              runSpacing: AppSpacing.space2,
              children: [
                for (final badge in badges)
                  AppBadge(
                    size: BadgeSize.sm,
                    variant: BadgeVariant.soft,
                    color: badge.color,
                    label: badge.label,
                  ),
              ],
            ),
            if (resolvedBranchName != null &&
                resolvedBranchName.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.space5),
              PatientBranchPill(branchName: resolvedBranchName),
            ],
          ],
        ),
      ),
    );
  }
}

BadgeColor _visitStatusColor(VisitStatus status) {
  return switch (status) {
    VisitStatus.inProgress => BadgeColor.info,
    VisitStatus.completed => BadgeColor.success,
  };
}

BadgeColor _appointmentTypeColor(AppointmentType type) {
  return switch (type) {
    AppointmentType.planned => BadgeColor.teal,
    AppointmentType.unknown => BadgeColor.neutral,
  };
}

BadgeColor _appointmentStatusColor(AppointmentStatus status) {
  return switch (status) {
    AppointmentStatus.scheduled => BadgeColor.neutral,
    AppointmentStatus.confirmed => BadgeColor.success,
    AppointmentStatus.checkedIn => BadgeColor.info,
    AppointmentStatus.inProgress => BadgeColor.info,
    AppointmentStatus.completed => BadgeColor.success,
    AppointmentStatus.cancelled => BadgeColor.danger,
    AppointmentStatus.noShow => BadgeColor.warning,
    AppointmentStatus.unknown => BadgeColor.neutral,
  };
}
