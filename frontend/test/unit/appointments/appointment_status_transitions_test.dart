import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status_transitions.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_type.dart';

void main() {
  group('appointment status transitions', () {
    AppointmentListItem item({
      AppointmentType type = AppointmentType.planned,
      AppointmentStatus status = AppointmentStatus.scheduled,
    }) {
      return AppointmentListItem(
        id: 'a',
        patientId: 'p',
        patientName: 'Pat',
        startTime: DateTime.utc(2026, 6, 1, 9),
        endTime: DateTime.utc(2026, 6, 1, 9, 30),
        type: type,
        status: status,
      );
    }

    test('planned scheduled offers check-in', () {
      final row = item();
      expect(forwardStatusTargetFor(row), AppointmentStatus.checkedIn);
      expect(forwardStatusActionLabelFor(row), 'Check in');
    });

    test('walk-in at checked_in hides check-in and offers start', () {
      final row = item(type: AppointmentType.walkIn, status: AppointmentStatus.checkedIn);
      expect(forwardStatusTargetFor(row), AppointmentStatus.inProgress);
      expect(forwardStatusActionLabelFor(row), 'Start');
    });

    test('terminal completed offers no forward action', () {
      final row = item(status: AppointmentStatus.completed);
      expect(forwardStatusTargetFor(row), isNull);
      expect(forwardStatusActionLabelFor(row), isEmpty);
    });

    test('invalid skip: scheduled walk-in has no check-in path', () {
      final row = item(type: AppointmentType.walkIn, status: AppointmentStatus.scheduled);
      expect(forwardStatusTargetFor(row), isNull);
    });
  });
}
