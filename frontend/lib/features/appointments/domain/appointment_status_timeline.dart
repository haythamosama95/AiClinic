import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';

/// Visual state for a step on the appointment status timeline.
enum AppointmentTimelineStepState { completed, current, upcoming, skipped }

/// Ordered lifecycle steps shown on the appointment detail timeline (V1-4).
abstract final class AppointmentStatusTimeline {
  static const List<AppointmentStatus> mainFlow = [
    AppointmentStatus.scheduled,
    AppointmentStatus.confirmed,
    AppointmentStatus.checkedIn,
    AppointmentStatus.inProgress,
    AppointmentStatus.completed,
  ];

  static bool isTerminalNegative(AppointmentStatus status) {
    return status == AppointmentStatus.cancelled || status == AppointmentStatus.noShow;
  }

  static AppointmentTimelineStepState stepState({required AppointmentStatus current, required AppointmentStatus step}) {
    if (isTerminalNegative(current)) {
      return AppointmentTimelineStepState.skipped;
    }

    final currentIndex = mainFlow.indexOf(current);
    final stepIndex = mainFlow.indexOf(step);
    if (currentIndex < 0 || stepIndex < 0) {
      return AppointmentTimelineStepState.skipped;
    }
    if (stepIndex < currentIndex) {
      return AppointmentTimelineStepState.completed;
    }
    if (stepIndex == currentIndex) {
      return AppointmentTimelineStepState.current;
    }
    return AppointmentTimelineStepState.upcoming;
  }

  static String stepDescription(AppointmentStatus status) {
    return switch (status) {
      AppointmentStatus.scheduled => 'The appointment is booked and waiting for staff or patient confirmation.',
      AppointmentStatus.confirmed => 'Attendance is confirmed — the patient is expected at the scheduled time.',
      AppointmentStatus.checkedIn => 'The patient has arrived and been registered at the front desk.',
      AppointmentStatus.inProgress => 'The doctor is actively seeing the patient during this visit.',
      AppointmentStatus.completed => 'The visit has finished and the appointment is fully closed.',
      AppointmentStatus.cancelled => 'The appointment was cancelled and will not take place.',
      AppointmentStatus.noShow => 'The patient did not arrive for the scheduled appointment.',
      AppointmentStatus.unknown => 'The current status could not be determined.',
    };
  }
}
