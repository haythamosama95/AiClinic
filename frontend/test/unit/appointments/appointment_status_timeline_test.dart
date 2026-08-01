import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status_timeline.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppointmentStatusTimeline', () {
    test('trivial: mainFlow lists lifecycle steps in order', () {
      expect(
        AppointmentStatusTimeline.mainFlow,
        [
          AppointmentStatus.scheduled,
          AppointmentStatus.confirmed,
          AppointmentStatus.checkedIn,
          AppointmentStatus.inProgress,
          AppointmentStatus.completed,
        ],
      );
    });

    test('advanced: isTerminalNegative is true only for cancelled and no-show', () {
      const terminalNegative = {AppointmentStatus.cancelled, AppointmentStatus.noShow};
      for (final status in AppointmentStatus.values) {
        expect(
          AppointmentStatusTimeline.isTerminalNegative(status),
          terminalNegative.contains(status),
        );
      }
    });

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

    test('advanced: stepState table for every main-flow current status', () {
      for (var currentIndex = 0; currentIndex < AppointmentStatusTimeline.mainFlow.length; currentIndex++) {
        final current = AppointmentStatusTimeline.mainFlow[currentIndex];
        for (var stepIndex = 0; stepIndex < AppointmentStatusTimeline.mainFlow.length; stepIndex++) {
          final step = AppointmentStatusTimeline.mainFlow[stepIndex];
          final state = AppointmentStatusTimeline.stepState(current: current, step: step);

          if (stepIndex < currentIndex) {
            expect(state, AppointmentTimelineStepState.completed, reason: '$step before $current');
          } else if (stepIndex == currentIndex) {
            expect(state, AppointmentTimelineStepState.current, reason: '$step is current for $current');
          } else {
            expect(state, AppointmentTimelineStepState.upcoming, reason: '$step after $current');
          }
        }
      }
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

    test('invalid state: unknown current or step is skipped', () {
      for (final step in AppointmentStatusTimeline.mainFlow) {
        expect(
          AppointmentStatusTimeline.stepState(current: AppointmentStatus.unknown, step: step),
          AppointmentTimelineStepState.skipped,
        );
      }

      for (final current in AppointmentStatusTimeline.mainFlow) {
        expect(
          AppointmentStatusTimeline.stepState(current: current, step: AppointmentStatus.unknown),
          AppointmentTimelineStepState.skipped,
        );
      }
    });

    test('advanced: stepDescription is non-empty for every status', () {
      final descriptions = <AppointmentStatus, String>{};
      for (final status in AppointmentStatus.values) {
        final description = AppointmentStatusTimeline.stepDescription(status);
        expect(description.trim(), isNotEmpty);
        descriptions[status] = description;
      }

      final uniqueDescriptions = descriptions.values.toSet();
      expect(uniqueDescriptions.length, descriptions.length);
    });
  });
}
