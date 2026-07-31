import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/queue/domain/queue_shift_doctors.dart';
import 'package:ai_clinic/features/queue/domain/queue_start_doctor.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status_transitions.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_type.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/clinic-management/domain/staff_list_item.dart';
import 'package:ai_clinic/features/shifts/domain/shift_list_item.dart';
import 'package:ai_clinic/features/shifts/domain/shift_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('appointment status transitions', () {
    final referenceUtc = DateTime.utc(2026, 6, 2);

    AppointmentListItem item({
      AppointmentStatus status = AppointmentStatus.scheduled,
      DateTime? startTime,
      String? doctorId,
      String id = 'a',
    }) {
      final start = startTime ?? DateTime.utc(2026, 6, 1, 9);
      return AppointmentListItem(
        id: id,
        patientId: 'p',
        patientName: 'Pat',
        doctorId: doctorId,
        startTime: start,
        endTime: start.add(const Duration(minutes: 30)),
        type: AppointmentType.planned,
        status: status,
      );
    }

    test('scheduled offers confirm', () {
      final row = item();
      expect(forwardStatusTargetFor(row, referenceUtc: referenceUtc), AppointmentStatus.confirmed);
      expect(forwardStatusActionLabelFor(row, referenceUtc: referenceUtc), 'Confirm');
    });

    test('confirmed offers check-in on appointment day', () {
      final row = item(status: AppointmentStatus.confirmed);
      expect(forwardStatusTargetFor(row, referenceUtc: referenceUtc), AppointmentStatus.checkedIn);
      expect(forwardStatusActionLabelFor(row, referenceUtc: referenceUtc), 'Check in');
    });

    test('confirmed hides check-in before appointment day', () {
      final row = item(status: AppointmentStatus.confirmed);
      expect(forwardStatusTargetFor(row, referenceUtc: DateTime.utc(2026, 5, 31)), isNull);
    });

    test('checked_in offers start when doctor is free', () {
      final row = item(status: AppointmentStatus.checkedIn, doctorId: 'doc-a');
      expect(
        forwardStatusTargetFor(row, referenceUtc: referenceUtc, siblingAppointments: [row]),
        AppointmentStatus.inProgress,
      );
      expect(forwardStatusActionLabelFor(row, referenceUtc: referenceUtc, siblingAppointments: [row]), 'Start');
    });

    test('checked_in hides start when doctor already has in-progress patient and no alternatives', () {
      final start = DateTime.utc(2026, 6, 1, 9);
      final active = item(status: AppointmentStatus.inProgress, startTime: start, doctorId: 'doc-a', id: 'active');
      final waiting = item(
        status: AppointmentStatus.checkedIn,
        startTime: start.add(const Duration(minutes: 30)),
        doctorId: 'doc-a',
        id: 'waiting',
      );
      final inProgressBlocked =
          (AppointmentListItem item, Iterable<AppointmentListItem> siblings) =>
              AppointmentQueueStartDoctor.isForwardInProgressBlocked(
                item: item,
                siblingAppointments: siblings,
              );
      expect(
        forwardStatusTargetFor(
          waiting,
          referenceUtc: referenceUtc,
          siblingAppointments: [active, waiting],
          inProgressBlocked: inProgressBlocked,
        ),
        isNull,
      );
    });

    test('checked_in offers start when preferred doctor is busy but another shift doctor is free', () {
      final shiftLookup = AppointmentQueueShiftDoctorLookup.fromShiftsAndDoctors(
        organizationTimezone: 'UTC',
        shifts: [
          ShiftListItem(
            id: 's1',
            branchId: 'b1',
            shiftDate: DateTime(2026, 6, 1),
            startTime: '09:00',
            endTime: '17:00',
            status: ShiftStatus.active,
            isUnassigned: false,
            assigneeNames: const ['Dr Alpha', 'Dr Beta'],
            assigneeCount: 2,
          ),
        ],
        doctors: const [
          StaffListItem(id: 'doc-a', fullName: 'Dr Alpha', role: StaffRole.doctor, isActive: true),
          StaffListItem(id: 'doc-b', fullName: 'Dr Beta', role: StaffRole.doctor, isActive: true),
        ],
      );
      final start = DateTime.utc(2026, 6, 1, 9);
      final active = item(status: AppointmentStatus.inProgress, startTime: start, doctorId: 'doc-a', id: 'active');
      final waiting = item(
        status: AppointmentStatus.checkedIn,
        startTime: start.add(const Duration(minutes: 30)),
        doctorId: 'doc-a',
        id: 'waiting',
      );
      expect(
        forwardStatusTargetFor(
          waiting,
          referenceUtc: referenceUtc,
          siblingAppointments: [active, waiting],
          inProgressBlocked: (item, siblings) =>
              AppointmentQueueStartDoctor.isForwardInProgressBlocked(
                item: item,
                siblingAppointments: siblings,
                shiftLookup: shiftLookup,
              ),
        ),
        AppointmentStatus.inProgress,
      );
    });

    test('in_progress does not offer complete (visit submit required)', () {
      final row = item(status: AppointmentStatus.inProgress);
      expect(forwardStatusTargetFor(row, referenceUtc: referenceUtc), isNull);
      expect(forwardStatusActionLabelFor(row, referenceUtc: referenceUtc), isEmpty);
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
      expect(canMarkNoShowAppointment(row, referenceUtc: DateTime.utc(2026, 5, 31)), isFalse);
      expect(canCancelOrNoShowAppointment(row, referenceUtc: DateTime.utc(2026, 5, 31)), isTrue);
    });

    test('no-show only on or after appointment day', () {
      final future = item();
      expect(canMarkNoShowAppointment(future, referenceUtc: DateTime.utc(2026, 5, 31)), isFalse);
      expect(canMarkNoShowAppointment(future, referenceUtc: referenceUtc), isTrue);
      expect(canCancelOrNoShowAppointment(future, referenceUtc: DateTime.utc(2026, 5, 31)), isTrue);
    });

    test('confirmed planned appointments cannot be rescheduled per spec', () {
      expect(canRescheduleAppointment(item()), isTrue);
      expect(canRescheduleAppointment(item(status: AppointmentStatus.confirmed)), isFalse);
    });

    test('revert targets previous step in main flow', () {
      expect(previousStatusTargetFor(item(status: AppointmentStatus.confirmed)), AppointmentStatus.scheduled);
      expect(revertStatusActionLabelFor(item(status: AppointmentStatus.confirmed)), 'Undo confirm');
      expect(previousStatusTargetFor(item(status: AppointmentStatus.checkedIn)), AppointmentStatus.confirmed);
      expect(revertStatusActionLabelFor(item(status: AppointmentStatus.checkedIn)), 'Undo check-in');
      expect(previousStatusTargetFor(item(status: AppointmentStatus.inProgress)), AppointmentStatus.checkedIn);
      expect(revertStatusActionLabelFor(item(status: AppointmentStatus.inProgress)), 'Undo start');
    });

    test('scheduled and terminal statuses cannot revert', () {
      expect(previousStatusTargetFor(item()), isNull);
      expect(canRevertAppointmentStatus(item()), isFalse);
      expect(previousStatusTargetFor(item(status: AppointmentStatus.completed)), isNull);
      expect(previousStatusTargetFor(item(status: AppointmentStatus.cancelled)), isNull);
    });
  });
}
