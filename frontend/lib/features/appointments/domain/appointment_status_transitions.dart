import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status_day_rules.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_type.dart';

/// Whether advancing [item] to in-progress is blocked by queue/doctor constraints.
typedef AppointmentInProgressBlockedPredicate =
    bool Function(
      AppointmentListItem item,
      Iterable<AppointmentListItem> siblingAppointments,
    );

bool _defaultInProgressBlocked(
  AppointmentListItem item,
  Iterable<AppointmentListItem> siblingAppointments,
) {
  final assignedDoctorId = item.doctorId?.trim();
  if (assignedDoctorId != null && assignedDoctorId.isNotEmpty) {
    return false;
  }

  return siblingAppointments.any(
    (other) =>
        other.id != item.id &&
        other.status == AppointmentStatus.inProgress &&
        (other.doctorId == null || other.doctorId!.trim().isEmpty),
  );
}

/// Previous lifecycle step for [item] when the user undoes the last status change.
AppointmentStatus? previousStatusTargetFor(AppointmentListItem item) {
  return switch (item.status) {
    AppointmentStatus.confirmed => AppointmentStatus.scheduled,
    AppointmentStatus.checkedIn => AppointmentStatus.confirmed,
    AppointmentStatus.inProgress => AppointmentStatus.checkedIn,
    _ => null,
  };
}

/// Whether [item] may revert one step to the previous status in the main flow.
bool canRevertAppointmentStatus(AppointmentListItem item) {
  return previousStatusTargetFor(item) != null;
}

/// Label for the revert action button.
String revertStatusActionLabelFor(AppointmentListItem item) {
  return switch (previousStatusTargetFor(item)) {
    AppointmentStatus.scheduled => 'Undo confirm',
    AppointmentStatus.confirmed => 'Undo check-in',
    AppointmentStatus.checkedIn => 'Undo start',
    _ => 'Undo status',
  };
}

/// Forward lifecycle target for [item] when the user taps the primary action (V1-4 US5).
AppointmentStatus? forwardStatusTargetFor(
  AppointmentListItem item, {
  String organizationTimezone = 'UTC',
  DateTime? referenceUtc,
  Iterable<AppointmentListItem> siblingAppointments = const [],
  AppointmentInProgressBlockedPredicate inProgressBlocked =
      _defaultInProgressBlocked,
}) {
  final target = switch (item.status) {
    AppointmentStatus.scheduled => AppointmentStatus.confirmed,
    AppointmentStatus.confirmed => AppointmentStatus.checkedIn,
    AppointmentStatus.checkedIn => AppointmentStatus.inProgress,
    _ => null,
  };
  if (target == null ||
      !canTransitionToStatusOnDate(
        target,
        item.startTime,
        organizationTimezone: organizationTimezone,
        referenceUtc: referenceUtc,
      )) {
    return null;
  }
  if (target == AppointmentStatus.inProgress &&
      inProgressBlocked(item, siblingAppointments)) {
    return null;
  }
  return target;
}

/// Whether a planned appointment may be rescheduled (V1-4 US6).
///
/// Per spec FR-010a, only `scheduled` appointments can be rescheduled. After phone
/// confirmation (`confirmed`), staff must cancel and re-book to change the slot.
bool canRescheduleAppointment(AppointmentListItem item) {
  return item.type == AppointmentType.planned &&
      item.status == AppointmentStatus.scheduled;
}

/// Whether cancel is allowed for [item] (V1-4 US7); may be done before the appointment day.
bool canCancelAppointment(AppointmentListItem item) {
  return item.status.canTransitionTo(AppointmentStatus.cancelled);
}

/// Whether no-show is allowed for [item] (V1-4 US7); only on or after the appointment day.
bool canMarkNoShowAppointment(
  AppointmentListItem item, {
  String organizationTimezone = 'UTC',
  DateTime? referenceUtc,
}) {
  if (!item.status.canTransitionTo(AppointmentStatus.noShow)) {
    return false;
  }
  return canTransitionToStatusOnDate(
    AppointmentStatus.noShow,
    item.startTime,
    organizationTimezone: organizationTimezone,
    referenceUtc: referenceUtc,
  );
}

/// Whether cancel or no-show actions should be offered for [item] (V1-4 US7).
bool canCancelOrNoShowAppointment(
  AppointmentListItem item, {
  String organizationTimezone = 'UTC',
  DateTime? referenceUtc,
}) {
  return canCancelAppointment(item) ||
      canMarkNoShowAppointment(
        item,
        organizationTimezone: organizationTimezone,
        referenceUtc: referenceUtc,
      );
}

/// Label for the next forward action button.
String forwardStatusActionLabelFor(
  AppointmentListItem item, {
  String organizationTimezone = 'UTC',
  DateTime? referenceUtc,
  Iterable<AppointmentListItem> siblingAppointments = const [],
  AppointmentInProgressBlockedPredicate inProgressBlocked =
      _defaultInProgressBlocked,
}) {
  return switch (forwardStatusTargetFor(
    item,
    organizationTimezone: organizationTimezone,
    referenceUtc: referenceUtc,
    siblingAppointments: siblingAppointments,
    inProgressBlocked: inProgressBlocked,
  )) {
    AppointmentStatus.confirmed => 'Confirm',
    AppointmentStatus.checkedIn => 'Check in',
    AppointmentStatus.inProgress => 'Start',
    _ => '',
  };
}
