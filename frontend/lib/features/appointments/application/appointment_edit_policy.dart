import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status_transitions.dart';

/// Single source for appointment edit and cancel eligibility (V1-4).
abstract final class AppointmentEditPolicy {
  /// Whether non-terminal fields (patient, doctor, notes) may be edited.
  static bool canEditAppointment(AppointmentStatus status) => !status.isTerminal;

  /// Whether the schedule (date/time slot) may be edited.
  ///
  /// Only [AppointmentStatus.scheduled] appointments can change their slot;
  /// confirmed and later statuses must cancel and re-book instead.
  static bool canEditSchedule(AppointmentStatus status) => status == AppointmentStatus.scheduled;

  /// Whether the booking sheet should skip the time-selection step in edit mode.
  static bool skipsTimeStep({required bool isEditMode, required AppointmentStatus status}) {
    return isEditMode && !canEditSchedule(status);
  }

  /// Context-menu / button label reflecting what kind of edit is offered.
  static String editActionLabel(AppointmentStatus status) {
    if (canEditAppointment(status) && !canEditSchedule(status)) {
      return 'Edit details';
    }
    return 'Edit appointment';
  }

  static String? editDisabledReason({required bool canEdit, required AppointmentStatus status}) {
    if (!canEdit) {
      return 'You do not have permission to edit appointments.';
    }
    if (status.isTerminal) {
      return '${status.label} appointments cannot be edited.';
    }
    return null;
  }

  static String? editDisabledReasonForDetail({required bool canEdit, required AppointmentStatus status}) {
    if (!canEdit) {
      return 'You do not have permission to manage appointments.';
    }
    if (status.isTerminal) {
      return 'This appointment is ${status.label.toLowerCase()} and cannot be edited.';
    }
    return null;
  }

  static String? cancelDisabledReason({required bool canCancel, required AppointmentListItem item}) {
    if (!canCancel) {
      return 'You do not have permission to cancel appointments.';
    }
    if (!canCancelAppointment(item)) {
      return '${item.status.label} appointments cannot be cancelled.';
    }
    return null;
  }
}
