import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_queue_shift_doctors.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_type.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/clinic-management/domain/staff_list_item.dart';
import 'package:ai_clinic/features/shifts/domain/shift_list_item.dart';
import 'package:ai_clinic/features/shifts/domain/shift_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppointmentQueueShiftDoctorLookup', () {
    final doctors = [
      const StaffListItem(id: 'd1', fullName: 'Dr Alpha', role: StaffRole.doctor, isActive: true),
      const StaffListItem(id: 'd2', fullName: 'Dr Beta', role: StaffRole.doctor, isActive: true),
    ];

    final morningShift = ShiftListItem(
      id: 's1',
      branchId: 'b1',
      shiftDate: DateTime(2026, 6, 4),
      startTime: '09:00',
      endTime: '13:00',
      status: ShiftStatus.active,
      isUnassigned: false,
      assigneeNames: const ['Dr Alpha', 'Dr Beta', 'Reception A'],
      assigneeCount: 3,
    );

    test('doctorsOnShiftAt returns only doctors covering appointment time', () {
      final lookup = AppointmentQueueShiftDoctorLookup.fromShiftsAndDoctors(
        organizationTimezone: 'UTC',
        shifts: [morningShift],
        doctors: doctors,
      );

      final onShift = lookup.doctorsOnShiftAt(DateTime.utc(2026, 6, 4, 10, 30));
      expect(onShift.map((doctor) => doctor.name), ['Dr Alpha', 'Dr Beta']);
      expect(onShift.map((doctor) => doctor.id), ['d1', 'd2']);
    });

    test('doctorsOnShiftAt excludes shifts outside appointment time', () {
      final lookup = AppointmentQueueShiftDoctorLookup.fromShiftsAndDoctors(
        organizationTimezone: 'UTC',
        shifts: [morningShift],
        doctors: doctors,
      );

      expect(lookup.doctorsOnShiftAt(DateTime.utc(2026, 6, 4, 14)), isEmpty);
    });

    test('doctorsOnCurrentShiftAt includes staffed shifts with unknown status', () {
      final unknownStatusShift = ShiftListItem(
        id: 's2',
        branchId: 'b1',
        shiftDate: DateTime(2026, 6, 4),
        startTime: '09:00',
        endTime: '13:00',
        status: ShiftStatus.unknown,
        isUnassigned: false,
        assigneeNames: const ['Dr Alpha'],
        assigneeCount: 1,
      );
      final lookup = AppointmentQueueShiftDoctorLookup.fromShiftsAndDoctors(
        organizationTimezone: 'UTC',
        shifts: [unknownStatusShift],
        doctors: doctors,
      );

      expect(lookup.doctorsOnCurrentShiftAt(DateTime.utc(2026, 6, 4, 10)), hasLength(1));
    });

    test('doctorsOnCurrentShiftAt falls back to staffed shifts on the same day', () {
      final lookup = AppointmentQueueShiftDoctorLookup.fromShiftsAndDoctors(
        organizationTimezone: 'UTC',
        shifts: [morningShift],
        doctors: doctors,
      );

      expect(lookup.doctorsOnCurrentShiftAt(DateTime.utc(2026, 6, 4, 14)).map((doctor) => doctor.name), [
        'Dr Alpha',
        'Dr Beta',
      ]);
      expect(lookup.doctorsOnShiftAt(DateTime.utc(2026, 6, 4, 14)), isEmpty);
    });

    test('presentationFor marks pre-visit assigned doctor as patient choice', () {
      final lookup = AppointmentQueueShiftDoctorLookup.empty;
      final item = _item(status: AppointmentStatus.confirmed, doctorId: 'd1', doctorName: 'Dr Alpha');

      final presentation = lookup.presentationFor(item);
      expect(presentation.entries, hasLength(1));
      expect(presentation.entries.first.name, 'Dr Alpha');
      expect(presentation.entries.first.isPatientChoice, isTrue);
    });

    test('presentationFor shows no preferred doctor when appointment is unassigned', () {
      final lookup = AppointmentQueueShiftDoctorLookup.fromShiftsAndDoctors(
        organizationTimezone: 'UTC',
        shifts: [morningShift],
        doctors: doctors,
      );
      final item = _item(startTime: DateTime.utc(2026, 6, 4, 10));

      final presentation = lookup.presentationFor(item);
      expect(presentation.entries, hasLength(1));
      expect(presentation.entries.first.name, 'No preferred doctor');
      expect(presentation.hasPatientChoice, isFalse);
    });

    test('presentationFor shows visit doctor without patient choice marker', () {
      final lookup = AppointmentQueueShiftDoctorLookup.empty;
      final item = _item(status: AppointmentStatus.inProgress, doctorId: 'd1', doctorName: 'Dr Alpha');

      final presentation = lookup.presentationFor(item);
      expect(presentation.entries.first.isPatientChoice, isFalse);
    });

    test('BUG-005: duplicate doctor names are excluded from shift lookup', () {
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
            assigneeNames: const ['Dr Alpha'],
            assigneeCount: 1,
          ),
        ],
        doctors: const [
          StaffListItem(id: 'd1', fullName: 'Dr Alpha', role: StaffRole.doctor, isActive: true),
          StaffListItem(id: 'd2', fullName: 'Dr Alpha', role: StaffRole.doctor, isActive: true),
        ],
      );

      expect(lookup.doctorsOnShiftAt(DateTime.utc(2026, 6, 4, 10)), isEmpty);
    });
  });
}

AppointmentListItem _item({
  AppointmentStatus status = AppointmentStatus.scheduled,
  DateTime? startTime,
  String? doctorId,
  String? doctorName,
}) {
  final start = startTime ?? DateTime.utc(2026, 6, 4, 10);
  return AppointmentListItem(
    id: 'a1',
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
