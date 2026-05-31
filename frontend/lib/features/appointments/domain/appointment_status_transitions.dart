import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status_day_rules.dart';

/// Forward lifecycle target for [item] when the user taps the primary action (V1-4 US5).
AppointmentStatus? forwardStatusTargetFor(AppointmentListItem item, {DateTime? reference}) {
  final target = switch (item.status) {
    AppointmentStatus.scheduled => AppointmentStatus.confirmed,
    AppointmentStatus.confirmed => AppointmentStatus.checkedIn,
    AppointmentStatus.checkedIn => AppointmentStatus.inProgress,
    _ => null,
  };
  if (target == null || !canTransitionToStatusOnDate(target, item.startTime, reference)) {
    return null;
  }
  return target;
}

/// Whether a planned appointment in `scheduled` status may be rescheduled (V1-4 US6).
bool canRescheduleAppointment(AppointmentListItem item) {
  return item.status == AppointmentStatus.scheduled;
}

/// Whether cancel is allowed for [item] (V1-4 US7); may be done before the appointment day.
bool canCancelAppointment(AppointmentListItem item) {
  return item.status.canTransitionTo(AppointmentStatus.cancelled);
}

/// Whether no-show is allowed for [item] (V1-4 US7); only on or after the appointment day.
bool canMarkNoShowAppointment(AppointmentListItem item, {DateTime? reference}) {
  if (!item.status.canTransitionTo(AppointmentStatus.noShow)) {
    return false;
  }
  return canTransitionToStatusOnDate(AppointmentStatus.noShow, item.startTime, reference);
}

/// Whether cancel or no-show actions should be offered for [item] (V1-4 US7).
bool canCancelOrNoShowAppointment(AppointmentListItem item, {DateTime? reference}) {
  return canCancelAppointment(item) || canMarkNoShowAppointment(item, reference: reference);
}

/// Label for the next forward action button.
String forwardStatusActionLabelFor(AppointmentListItem item, {DateTime? reference}) {
  return switch (forwardStatusTargetFor(item, reference: reference)) {
    AppointmentStatus.confirmed => 'Confirm',
    AppointmentStatus.checkedIn => 'Check in',
    AppointmentStatus.inProgress => 'Start',
    _ => '',
  };
}
