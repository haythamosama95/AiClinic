import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status_transitions.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_type.dart';

void main() {
  group('appointment status transitions', () {
    final reference = DateTime(2026, 6, 2);

    AppointmentListItem item({AppointmentStatus status = AppointmentStatus.scheduled, DateTime? startTime}) {
      final start = startTime ?? DateTime.utc(2026, 6, 1, 9);
      return AppointmentListItem(
        id: 'a',
        patientId: 'p',
        patientName: 'Pat',
        startTime: start,
        endTime: start.add(const Duration(minutes: 30)),
        type: AppointmentType.planned,
        status: status,
      );
    }

    test('scheduled offers confirm', () {
      final row = item();
      expect(forwardStatusTargetFor(row, reference: reference), AppointmentStatus.confirmed);
      expect(forwardStatusActionLabelFor(row, reference: reference), 'Confirm');
    });

    test('confirmed offers check-in on appointment day', () {
      final row = item(status: AppointmentStatus.confirmed);
      expect(forwardStatusTargetFor(row, reference: reference), AppointmentStatus.checkedIn);
      expect(forwardStatusActionLabelFor(row, reference: reference), 'Check in');
    });

    test('confirmed hides check-in before appointment day', () {
      final row = item(status: AppointmentStatus.confirmed);
      expect(forwardStatusTargetFor(row, reference: DateTime(2026, 5, 31)), isNull);
    });

    test('checked_in offers start', () {
      final row = item(status: AppointmentStatus.checkedIn);
      expect(forwardStatusTargetFor(row, reference: reference), AppointmentStatus.inProgress);
      expect(forwardStatusActionLabelFor(row, reference: reference), 'Start');
    });

    test('in_progress does not offer complete (visit submit required)', () {
      final row = item(status: AppointmentStatus.inProgress);
      expect(forwardStatusTargetFor(row, reference: reference), isNull);
      expect(forwardStatusActionLabelFor(row, reference: reference), isEmpty);
    });

    test('terminal completed offers no forward action', () {
      final row = item(status: AppointmentStatus.completed);
      expect(forwardStatusTargetFor(row), isNull);
      expect(forwardStatusActionLabelFor(row), isEmpty);
    });

    test('cancel allowed from scheduled, confirmed, and checked_in', () {
      expect(canCancelAppointment(item()), isTrue);
      expect(canCancelAppointment(item(status: AppointmentStatus.confirmed)), isTrue);
      expect(canCancelAppointment(item(status: AppointmentStatus.checkedIn)), isTrue);
      expect(canCancelAppointment(item(status: AppointmentStatus.completed)), isFalse);
    });

    test('confirmed can cancel before appointment day', () {
      final row = item(status: AppointmentStatus.confirmed);
      expect(canCancelAppointment(row), isTrue);
      expect(canMarkNoShowAppointment(row, reference: DateTime(2026, 5, 31)), isFalse);
      expect(canCancelOrNoShowAppointment(row, reference: DateTime(2026, 5, 31)), isTrue);
    });

    test('no-show only on or after appointment day', () {
      final future = item();
      expect(canMarkNoShowAppointment(future, reference: DateTime(2026, 5, 31)), isFalse);
      expect(canMarkNoShowAppointment(future, reference: reference), isTrue);
      expect(canCancelOrNoShowAppointment(future, reference: DateTime(2026, 5, 31)), isTrue);
    });
  });
}
