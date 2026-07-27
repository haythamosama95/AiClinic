import 'package:ai_clinic/core/ui/models/booking_slot.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_booking_slots.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_type.dart';
import 'package:ai_clinic/core/domain/clinic/branch_working_schedule.dart';
import 'package:ai_clinic/core/domain/clinic/staff_list_item.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppointmentBookingSlots', () {
    final schedule = BranchWorkingSchedule.defaultSchedule();
    final doctors = [
      const StaffListItem(
        id: 'doc-1',
        fullName: 'Dr. Ada',
        role: StaffRole.doctor,
        isActive: true,
        branches: [StaffBranchLabel(id: 'branch-1', name: 'Main')],
      ),
      const StaffListItem(
        id: 'doc-2',
        fullName: 'Dr. Ben',
        role: StaffRole.doctor,
        isActive: true,
        branches: [StaffBranchLabel(id: 'branch-1', name: 'Main')],
      ),
    ];

    test('marks slot preferred when preferred doctor is free', () {
      final day = DateTime(2026, 7, 13, 0, 0);
      final slots = AppointmentBookingSlots.slotsForDay(
        schedule: schedule,
        date: day,
        slotMinutes: 30,
        durationMinutes: 30,
        branchDoctors: doctors,
        existingAppointments: const [],
        preferredDoctorId: 'doc-1',
      );

      expect(slots, isNotEmpty);
      expect(slots.first.status, BookingSlotStatus.preferred);
      expect(slots.first.label, isEmpty);
    });

    test('marks slot alternate when only other doctors are free', () {
      final day = DateTime(2026, 7, 13, 0, 0);
      final occupiedStart = DateTime(2026, 7, 13, 9, 0);
      final appointments = [
        AppointmentListItem(
          id: 'appt-1',
          patientId: 'patient-1',
          patientName: 'Patient',
          doctorId: 'doc-1',
          doctorName: 'Dr. Ada',
          startTime: occupiedStart,
          endTime: occupiedStart.add(const Duration(minutes: 30)),
          type: AppointmentType.planned,
          status: AppointmentStatus.scheduled,
        ),
      ];

      final slots = AppointmentBookingSlots.slotsForDay(
        schedule: schedule,
        date: day,
        slotMinutes: 30,
        durationMinutes: 30,
        branchDoctors: doctors,
        existingAppointments: appointments,
        preferredDoctorId: 'doc-1',
      );

      final nineAm = slots.firstWhere((slot) => slot.start.hour == 9 && slot.start.minute == 0);
      expect(nineAm.status, BookingSlotStatus.alternate);
      expect(nineAm.availableDoctorIds, contains('doc-2'));
    });

    test('marks slot locked when all doctors are booked', () {
      final day = DateTime(2026, 7, 13, 0, 0);
      final occupiedStart = DateTime(2026, 7, 13, 9, 0);
      final appointments = [
        AppointmentListItem(
          id: 'appt-1',
          patientId: 'patient-1',
          patientName: 'Patient A',
          doctorId: 'doc-1',
          doctorName: 'Dr. Ada',
          startTime: occupiedStart,
          endTime: occupiedStart.add(const Duration(minutes: 30)),
          type: AppointmentType.planned,
          status: AppointmentStatus.scheduled,
        ),
        AppointmentListItem(
          id: 'appt-2',
          patientId: 'patient-2',
          patientName: 'Patient B',
          doctorId: 'doc-2',
          doctorName: 'Dr. Ben',
          startTime: occupiedStart,
          endTime: occupiedStart.add(const Duration(minutes: 30)),
          type: AppointmentType.planned,
          status: AppointmentStatus.scheduled,
        ),
      ];

      final slots = AppointmentBookingSlots.slotsForDay(
        schedule: schedule,
        date: day,
        slotMinutes: 30,
        durationMinutes: 30,
        branchDoctors: doctors,
        existingAppointments: appointments,
        preferredDoctorId: 'doc-1',
      );

      final nineAm = slots.firstWhere((slot) => slot.start.hour == 9 && slot.start.minute == 0);
      expect(nineAm.status, BookingSlotStatus.locked);
    });
  });
}
