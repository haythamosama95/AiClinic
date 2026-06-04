import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status_day_rules.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_type.dart';

/// Forward lifecycle target for [item] when the user taps the primary action (V1-4 US5).
AppointmentStatus? forwardStatusTargetFor(
  AppointmentListItem item, {
  String organizationTimezone = 'UTC',
  DateTime? referenceUtc,
}) {
  final target = switch (item.status) {
    AppointmentStatus.scheduled => AppointmentStatus.confirmed,
    AppointmentStatus.confirmed => AppointmentStatus.checkedIn,
    AppointmentStatus.checkedIn => AppointmentStatus.inProgress,
    AppointmentStatus.inProgress => AppointmentStatus.completed,
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
  return target;
}

/// Whether a planned appointment may be rescheduled (V1-4 US6).
///
/// Per spec FR-010a, only `scheduled` appointments can be rescheduled. After phone
/// confirmation (`confirmed`), staff must cancel and re-book to change the slot.
bool canRescheduleAppointment(AppointmentListItem item) {
  return item.type == AppointmentType.planned && item.status == AppointmentStatus.scheduled;
}

/// Whether cancel is allowed for [item] (V1-4 US7); may be done before the appointment day.
bool canCancelAppointment(AppointmentListItem item) {
  return item.status.canTransitionTo(AppointmentStatus.cancelled);
}

/// Whether no-show is allowed for [item] (V1-4 US7); only on or after the appointment day.
bool canMarkNoShowAppointment(AppointmentListItem item, {String organizationTimezone = 'UTC', DateTime? referenceUtc}) {
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
      canMarkNoShowAppointment(item, organizationTimezone: organizationTimezone, referenceUtc: referenceUtc);
}

/// Label for the next forward action button.
String forwardStatusActionLabelFor(
  AppointmentListItem item, {
  String organizationTimezone = 'UTC',
  DateTime? referenceUtc,
}) {
  return switch (forwardStatusTargetFor(item, organizationTimezone: organizationTimezone, referenceUtc: referenceUtc)) {
    AppointmentStatus.confirmed => 'Confirm',
    AppointmentStatus.checkedIn => 'Check in',
    AppointmentStatus.inProgress => 'Start',
    AppointmentStatus.completed => 'Complete',
    _ => '',
  };
}
