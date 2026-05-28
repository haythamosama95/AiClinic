import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status_transitions.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_type.dart';

void main() {
  group('appointment status transitions', () {
    AppointmentListItem item({AppointmentStatus status = AppointmentStatus.scheduled}) {
      return AppointmentListItem(
        id: 'a',
        patientId: 'p',
        patientName: 'Pat',
        startTime: DateTime.utc(2026, 6, 1, 9),
        endTime: DateTime.utc(2026, 6, 1, 9, 30),
        type: AppointmentType.planned,
        status: status,
      );
    }

    test('scheduled offers confirm', () {
      final row = item();
      expect(forwardStatusTargetFor(row), AppointmentStatus.confirmed);
      expect(forwardStatusActionLabelFor(row), 'Confirm');
    });

    test('confirmed offers check-in', () {
      final row = item(status: AppointmentStatus.confirmed);
      expect(forwardStatusTargetFor(row), AppointmentStatus.checkedIn);
      expect(forwardStatusActionLabelFor(row), 'Check in');
    });

    test('checked_in offers start', () {
      final row = item(status: AppointmentStatus.checkedIn);
      expect(forwardStatusTargetFor(row), AppointmentStatus.inProgress);
      expect(forwardStatusActionLabelFor(row), 'Start');
    });

    test('terminal completed offers no forward action', () {
      final row = item(status: AppointmentStatus.completed);
      expect(forwardStatusTargetFor(row), isNull);
      expect(forwardStatusActionLabelFor(row), isEmpty);
    });

    test('cancel allowed from scheduled, confirmed, and checked_in', () {
      expect(canCancelOrNoShowAppointment(item()), isTrue);
      expect(canCancelOrNoShowAppointment(item(status: AppointmentStatus.confirmed)), isTrue);
      expect(canCancelOrNoShowAppointment(item(status: AppointmentStatus.checkedIn)), isTrue);
      expect(canCancelOrNoShowAppointment(item(status: AppointmentStatus.completed)), isFalse);
    });
  });
}
