import 'package:ai_clinic/features/appointments/domain/appointment_shift_doctor_resolution.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/core/domain/clinic/staff_list_item.dart';
import 'package:ai_clinic/features/shifts/domain/shift_branch_staff.dart';
import 'package:ai_clinic/features/shifts/domain/shift_list_item.dart';
import 'package:ai_clinic/features/shifts/domain/shift_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveShiftDoctors', () {
    const branchDoctors = [
      ShiftBranchStaffMember(id: 'd1', fullName: 'Dr Alpha', role: StaffRole.doctor),
      ShiftBranchStaffMember(id: 'd2', fullName: 'Dr Beta', role: StaffRole.doctor),
    ];

    const fallbackDoctors = [
      StaffListItem(id: 'd1', fullName: 'Dr Alpha', role: StaffRole.doctor, isActive: true),
      StaffListItem(id: 'd2', fullName: 'Dr Beta', role: StaffRole.doctor, isActive: true),
      StaffListItem(id: 'd3', fullName: 'Dr Gamma', role: StaffRole.doctor, isActive: true),
    ];

    test('includes branch doctors assigned to shifts by id', () {
      final doctors = resolveShiftDoctors(
        branchStaff: branchDoctors,
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
        fallbackStaff: fallbackDoctors,
      );

      expect(doctors.map((doctor) => doctor.id), ['d1', 'd2']);
    });

    test('matches shift assignees by id, not display name', () {
      final doctors = resolveShiftDoctors(
        branchStaff: const [],
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
            assigneeIds: const ['d3'],
            assigneeCount: 1,
          ),
        ],
        fallbackStaff: fallbackDoctors,
      );

      expect(doctors.map((doctor) => doctor.id), ['d3']);
    });

    test('falls back to all branch doctors when no assignee ids match', () {
      final doctors = resolveShiftDoctors(
        branchStaff: branchDoctors,
        shifts: const [],
        fallbackStaff: fallbackDoctors,
      );

      expect(doctors.map((doctor) => doctor.id), ['d1', 'd2']);
    });

    test('falls back to active org doctors when branch staff is empty', () {
      final doctors = resolveShiftDoctors(
        branchStaff: const [],
        shifts: const [],
        fallbackStaff: fallbackDoctors,
      );

      expect(doctors.map((doctor) => doctor.id), ['d1', 'd2', 'd3']);
    });

    test('does not match org doctor by name when assignee id differs', () {
      final doctors = resolveShiftDoctors(
        branchStaff: const [],
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
            assigneeIds: const ['unknown-id'],
            assigneeCount: 1,
          ),
        ],
        fallbackStaff: fallbackDoctors,
      );

      expect(doctors.map((doctor) => doctor.id), ['d1', 'd2', 'd3']);
    });
  });
}
