import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_type.dart';

/// Forward lifecycle target for [item] when the user taps the primary action (V1-4 US5).
AppointmentStatus? forwardStatusTargetFor(AppointmentListItem item) {
  return switch (item.status) {
    AppointmentStatus.scheduled when item.type == AppointmentType.planned => AppointmentStatus.checkedIn,
    AppointmentStatus.checkedIn => AppointmentStatus.inProgress,
    AppointmentStatus.inProgress => AppointmentStatus.completed,
    _ => null,
  };
}

/// Label for the next forward action button.
String forwardStatusActionLabelFor(AppointmentListItem item) {
  return switch (forwardStatusTargetFor(item)) {
    AppointmentStatus.checkedIn => 'Check in',
    AppointmentStatus.inProgress => 'Start',
    AppointmentStatus.completed => 'Complete',
    _ => '',
  };
}
