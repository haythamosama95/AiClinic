import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_queue_shift_doctors.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_queue_start_doctor.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_type.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/core/domain/clinic/staff_list_item.dart';
import 'package:ai_clinic/features/shifts/domain/shift_list_item.dart';
import 'package:ai_clinic/features/shifts/domain/shift_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppointmentQueueStartDoctor', () {
    final lookup = AppointmentQueueShiftDoctorLookup.fromShiftsAndDoctors(
      organizationTimezone: 'UTC',
      shifts: [
        ShiftListItem(
          id: 's1',
          branchId: 'b1',
          shiftDate: DateTime(2026, 6, 4),
          startTime: '09:00',
          endTime: '17:00',
          status: ShiftStatus.active,
          isUnassigned: false,
          assigneeNames: const ['Dr Alpha', 'Dr Beta'],
          assigneeIds: const ['d1', 'd2'],
          assigneeCount: 2,
        ),
      ],
      doctors: const [
        StaffListItem(id: 'd1', fullName: 'Dr Alpha', role: StaffRole.doctor, isActive: true),
        StaffListItem(id: 'd2', fullName: 'Dr Beta', role: StaffRole.doctor, isActive: true),
      ],
    );

    test('requiresDoctorPicker when multiple doctors are on shift and appointment is unassigned', () {
      final item = _item(status: AppointmentStatus.checkedIn);

      expect(AppointmentQueueStartDoctor.requiresDoctorPicker(item: item, shiftLookup: lookup), isTrue);
    });

    test('requiresDoctorPicker when assigned preferred doctor is available', () {
      final item = _item(status: AppointmentStatus.checkedIn, doctorId: 'd1', doctorName: 'Dr Alpha');

      expect(AppointmentQueueStartDoctor.requiresDoctorPicker(item: item, shiftLookup: lookup), isFalse);
    });

    test('requiresDoctorPicker when only one doctor is on shift', () {
      final singleDoctorLookup = AppointmentQueueShiftDoctorLookup.fromShiftsAndDoctors(
        organizationTimezone: 'UTC',
        shifts: [
          ShiftListItem(
            id: 's1',
            branchId: 'b1',
            shiftDate: DateTime(2026, 6, 4),
            startTime: '09:00',
            endTime: '17:00',
            status: ShiftStatus.active,
            isUnassigned: false,
            assigneeNames: const ['Dr Alpha'],
            assigneeIds: const ['d1'],
            assigneeCount: 1,
          ),
        ],
        doctors: const [StaffListItem(id: 'd1', fullName: 'Dr Alpha', role: StaffRole.doctor, isActive: true)],
      );
      final item = _item(status: AppointmentStatus.checkedIn);

      expect(AppointmentQueueStartDoctor.requiresDoctorPicker(item: item, shiftLookup: singleDoctorLookup), isTrue);
    });

    test('optionsForStart marks preferred doctor on shift', () {
      final item = _item(status: AppointmentStatus.checkedIn, doctorId: 'd1', doctorName: 'Dr Alpha');

      final options = AppointmentQueueStartDoctor.optionsForStart(
        item: item,
        siblingAppointments: [item],
        shiftLookup: lookup,
      );

      expect(options, hasLength(2));
      expect(options.firstWhere((option) => option.id == 'd1').isPreferred, isTrue);
      expect(options.firstWhere((option) => option.id == 'd2').isPreferred, isFalse);
    });

    test('optionsForStart includes preferred doctor when not on shift', () {
      final item = _item(status: AppointmentStatus.checkedIn, doctorId: 'd9', doctorName: 'Dr Off Shift');

      final options = AppointmentQueueStartDoctor.optionsForStart(
        item: item,
        siblingAppointments: [item],
        shiftLookup: lookup,
      );

      expect(options.first.id, 'd9');
      expect(options.first.isPreferred, isTrue);
      expect(options, hasLength(3));
    });

    test('shiftOptionsFor marks busy doctors', () {
      final start = DateTime.utc(2026, 6, 4, 11);
      final active = _item(
        status: AppointmentStatus.inProgress,
        startTime: start,
        doctorId: 'd1',
        doctorName: 'Dr Alpha',
        id: 'active',
      );
      final waiting = _item(status: AppointmentStatus.checkedIn, startTime: start.add(const Duration(minutes: 30)));

      final options = AppointmentQueueStartDoctor.shiftOptionsFor(
        item: waiting,
        siblingAppointments: [active, waiting],
        shiftLookup: lookup,
      );

      expect(options, hasLength(2));
      expect(options.firstWhere((option) => option.id == 'd1').isBusy, isTrue);
      expect(options.firstWhere((option) => option.id == 'd2').isBusy, isFalse);
    });

    test('blockReasonForStart allows start when one of multiple shift doctors is free', () {
      final start = DateTime.utc(2026, 6, 4, 11);
      final active = _item(
        status: AppointmentStatus.inProgress,
        startTime: start,
        doctorId: 'd1',
        doctorName: 'Dr Alpha',
        id: 'active',
      );
      final waiting = _item(status: AppointmentStatus.checkedIn, startTime: start.add(const Duration(minutes: 30)));

      expect(
        AppointmentQueueStartDoctor.blockReasonForStart(
          item: waiting,
          siblingAppointments: [active, waiting],
          shiftLookup: lookup,
        ),
        isNull,
      );
    });

    test('blockReasonForStart allows start when preferred doctor is busy but another shift doctor is free', () {
      final start = DateTime.utc(2026, 6, 4, 11);
      final active = _item(
        status: AppointmentStatus.inProgress,
        startTime: start,
        doctorId: 'd1',
        doctorName: 'Dr Alpha',
        id: 'active',
      );
      final waiting = _item(
        status: AppointmentStatus.checkedIn,
        startTime: start.add(const Duration(minutes: 30)),
        doctorId: 'd1',
        doctorName: 'Dr Alpha',
        id: 'waiting',
      );

      expect(
        AppointmentQueueStartDoctor.blockReasonForStart(
          item: waiting,
          siblingAppointments: [active, waiting],
          shiftLookup: lookup,
        ),
        isNull,
      );
    });

    test('blockReasonForStart blocks when preferred doctor is busy and no shift doctor is free', () {
      final start = DateTime.utc(2026, 6, 4, 11);
      final activeAlpha = _item(
        status: AppointmentStatus.inProgress,
        startTime: start,
        doctorId: 'd1',
        doctorName: 'Dr Alpha',
        id: 'active-alpha',
      );
      final activeBeta = _item(
        status: AppointmentStatus.inProgress,
        startTime: start,
        doctorId: 'd2',
        doctorName: 'Dr Beta',
        id: 'active-beta',
      );
      final waiting = _item(
        status: AppointmentStatus.checkedIn,
        startTime: start.add(const Duration(minutes: 30)),
        doctorId: 'd1',
        doctorName: 'Dr Alpha',
        id: 'waiting',
      );

      expect(
        AppointmentQueueStartDoctor.blockReasonForStart(
          item: waiting,
          siblingAppointments: [activeAlpha, activeBeta, waiting],
          shiftLookup: lookup,
        ),
        'Dr Alpha already has a patient in progress. Complete that visit before starting another.',
      );
    });

    test('requiresDoctorPicker when preferred doctor is busy and another shift doctor is free', () {
      final start = DateTime.utc(2026, 6, 4, 11);
      final active = _item(
        status: AppointmentStatus.inProgress,
        startTime: start,
        doctorId: 'd1',
        doctorName: 'Dr Alpha',
        id: 'active',
      );
      final waiting = _item(
        status: AppointmentStatus.checkedIn,
        startTime: start.add(const Duration(minutes: 30)),
        doctorId: 'd1',
        doctorName: 'Dr Alpha',
        id: 'waiting',
      );

      expect(
        AppointmentQueueStartDoctor.requiresDoctorPicker(
          item: waiting,
          shiftLookup: lookup,
          siblingAppointments: [active, waiting],
        ),
        isTrue,
      );
    });
    test('blockReasonForStart does not block assigned waiting patient when unassigned visit is in progress', () {
      final start = DateTime.utc(2026, 6, 4, 11);
      final active = _item(
        status: AppointmentStatus.inProgress,
        startTime: start,
        doctorId: null,
        doctorName: null,
        id: 'active',
      );
      final waiting = _item(
        status: AppointmentStatus.checkedIn,
        startTime: start.add(const Duration(minutes: 30)),
        doctorId: 'd2',
        doctorName: 'Dr Beta',
        id: 'waiting',
      );

      expect(
        AppointmentQueueStartDoctor.blockReasonForStart(
          item: waiting,
          siblingAppointments: [active, waiting],
          shiftLookup: lookup,
        ),
        isNull,
      );
    });

    test('BUG-009: blockReasonForStart explains shared unassigned in-progress slot for unassigned waiting patient', () {
      final start = DateTime.utc(2026, 6, 4, 11);
      final active = _item(
        status: AppointmentStatus.inProgress,
        startTime: start,
        doctorId: null,
        doctorName: null,
        id: 'active',
      );
      final waiting = _item(status: AppointmentStatus.checkedIn, startTime: start.add(const Duration(minutes: 30)));

      expect(
        AppointmentQueueStartDoctor.blockReasonForStart(
          item: waiting,
          siblingAppointments: [active, waiting],
          shiftLookup: lookup,
        ),
        'Another visit without an assigned doctor is already in progress. Complete that visit or assign a doctor before starting another.',
      );
    });
  });
}

AppointmentListItem _item({
  AppointmentStatus status = AppointmentStatus.scheduled,
  DateTime? startTime,
  String? doctorId,
  String? doctorName,
  String id = 'a1',
}) {
  final start = startTime ?? DateTime.utc(2026, 6, 4, 10);
  return AppointmentListItem(
    id: id,
    patientId: 'p1',
    patientName: 'Pat',
    doctorId: doctorId,
    doctorName: doctorName,
    startTime: start,
    endTime: start.add(const Duration(minutes: 30)),
    type: AppointmentType.planned,
    status: status,
  );
}
