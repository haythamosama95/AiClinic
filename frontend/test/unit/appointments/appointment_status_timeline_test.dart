import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status_timeline.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppointmentStatusTimeline', () {
    test('main flow marks completed, current, and upcoming steps', () {
      expect(
        AppointmentStatusTimeline.stepState(current: AppointmentStatus.checkedIn, step: AppointmentStatus.scheduled),
        AppointmentTimelineStepState.completed,
      );
      expect(
        AppointmentStatusTimeline.stepState(current: AppointmentStatus.checkedIn, step: AppointmentStatus.confirmed),
        AppointmentTimelineStepState.completed,
      );
      expect(
        AppointmentStatusTimeline.stepState(current: AppointmentStatus.checkedIn, step: AppointmentStatus.checkedIn),
        AppointmentTimelineStepState.current,
      );
      expect(
        AppointmentStatusTimeline.stepState(current: AppointmentStatus.checkedIn, step: AppointmentStatus.inProgress),
        AppointmentTimelineStepState.upcoming,
      );
    });

    test('terminal negative statuses skip main flow steps', () {
      for (final step in AppointmentStatusTimeline.mainFlow) {
        expect(
          AppointmentStatusTimeline.stepState(current: AppointmentStatus.cancelled, step: step),
          AppointmentTimelineStepState.skipped,
        );
        expect(
          AppointmentStatusTimeline.stepState(current: AppointmentStatus.noShow, step: step),
          AppointmentTimelineStepState.skipped,
        );
      }
    });
  });
}
