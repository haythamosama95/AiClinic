import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/l10n/app_localizations_x.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_type.dart';
import 'package:ai_clinic/features/appointments/presentation/formatting/appointment_queue_labels.dart';
import 'package:ai_clinic/features/patients/presentation/widgets/patient_branch_pill.dart';
import 'package:ai_clinic/features/patients/presentation/widgets/patient_date_stamp.dart';
import 'package:ai_clinic/features/patients/presentation/widgets/patient_record_card.dart';
import 'package:ai_clinic/features/visits/domain/visit_list_item.dart';
import 'package:ai_clinic/features/visits/domain/visit_status.dart';
import 'package:ai_clinic/features/visits/presentation/utils/visit_status_presentation.dart';
import 'package:ai_clinic/l10n/app_localizations.dart';

/// Unified visit/appointment record card for the patient detail Visits tab.
class PatientVisitRecordCard extends StatelessWidget {
  const PatientVisitRecordCard._({
    required this.date,
    required this.doctorName,
    required this.badges,
    this.branchName,
    super.key,
  });

  factory PatientVisitRecordCard.fromVisit(BuildContext context, VisitListItem visit, {Key? key}) {
    final l10n = context.l10n;

    return PatientVisitRecordCard._(
      key: key,
      date: visit.visitDate,
      doctorName: visit.doctorName,
      badges: [
        (label: _appointmentTypeLabel(l10n, AppointmentType.planned), color: _appointmentTypeColor(AppointmentType.planned)),
        (label: _visitStatusLabel(l10n, visit.status), color: VisitStatusPresentation.badgeColor(visit.status)),
      ],
      branchName: visit.branchName,
    );
  }

  factory PatientVisitRecordCard.fromAppointment(
    BuildContext context,
    AppointmentListItem appointment, {
    String? branchName,
    Key? key,
  }) {
    final l10n = context.l10n;
    final resolvedBranchName = branchName?.trim();

    return PatientVisitRecordCard._(
      key: key,
      date: appointment.startTime,
      doctorName: appointment.doctorDisplayName,
      badges: [
        (label: _appointmentTypeLabel(l10n, appointment.type), color: _appointmentTypeColor(appointment.type)),
        (
          label: _appointmentStatusLabel(l10n, appointment.status),
          color: _badgeColorForTone(AppointmentQueueLabels.scheduleBadgeTone(appointment.status)),
        ),
      ],
      branchName: resolvedBranchName?.isNotEmpty == true ? resolvedBranchName : null,
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
              style: AppTypography.bodyStrong(context).copyWith(color: colors.textPrimary),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: AppSpacing.space5),
            Wrap(
              spacing: AppSpacing.space2,
              runSpacing: AppSpacing.space2,
              children: [
                for (final badge in badges)
                  AppBadge(size: BadgeSize.sm, variant: BadgeVariant.soft, color: badge.color, label: badge.label),
              ],
            ),
            if (resolvedBranchName != null && resolvedBranchName.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.space5),
              PatientBranchPill(branchName: resolvedBranchName),
            ],
          ],
        ),
      ),
    );
  }
}

String _appointmentTypeLabel(AppLocalizations l10n, AppointmentType type) {
  return switch (type) {
    AppointmentType.planned => l10n.appointmentTypePlanned,
    AppointmentType.unknown => l10n.appointmentTypeUnknown,
  };
}

String _visitStatusLabel(AppLocalizations l10n, VisitStatus status) {
  return switch (status) {
    VisitStatus.inProgress => l10n.visitStatusInProgress,
    VisitStatus.completed => l10n.visitStatusCompleted,
  };
}

String _appointmentStatusLabel(AppLocalizations l10n, AppointmentStatus status) {
  return switch (status) {
    AppointmentStatus.scheduled => l10n.appointmentStatusScheduled,
    AppointmentStatus.confirmed => l10n.appointmentStatusConfirmed,
    AppointmentStatus.checkedIn => l10n.appointmentStatusCheckedIn,
    AppointmentStatus.inProgress => l10n.appointmentStatusInProgress,
    AppointmentStatus.completed => l10n.appointmentStatusCompleted,
    AppointmentStatus.cancelled => l10n.appointmentStatusCancelled,
    AppointmentStatus.noShow => l10n.appointmentStatusNoShow,
    AppointmentStatus.unknown => l10n.appointmentStatusUnknown,
  };
}

BadgeColor _badgeColorForTone(AppBadgeTone tone) {
  return switch (tone) {
    AppBadgeTone.neutral => BadgeColor.neutral,
    AppBadgeTone.info => BadgeColor.info,
    AppBadgeTone.success => BadgeColor.success,
    AppBadgeTone.warning => BadgeColor.warning,
    AppBadgeTone.destructive => BadgeColor.danger,
    AppBadgeTone.muted => BadgeColor.neutral,
  };
}

BadgeColor _appointmentTypeColor(AppointmentType type) {
  return switch (type) {
    AppointmentType.planned => BadgeColor.teal,
    AppointmentType.unknown => BadgeColor.neutral,
  };
}
