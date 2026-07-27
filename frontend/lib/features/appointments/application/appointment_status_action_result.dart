import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';

/// Outcome of an appointment status action orchestrated by [AppointmentStatusService].
sealed class AppointmentStatusActionResult {
  const AppointmentStatusActionResult();
}

/// Status transition completed successfully.
final class AppointmentStatusActionSuccess extends AppointmentStatusActionResult {
  const AppointmentStatusActionSuccess(this.status);

  final AppointmentStatus status;
}

/// Status transition failed; [doctorWasReassigned] is true when a doctor reassignment
/// RPC succeeded but the subsequent status update did not.
final class AppointmentStatusActionFailed extends AppointmentStatusActionResult {
  const AppointmentStatusActionFailed(this.userMessage, {required this.doctorWasReassigned});

  final String userMessage;
  final bool doctorWasReassigned;
}
