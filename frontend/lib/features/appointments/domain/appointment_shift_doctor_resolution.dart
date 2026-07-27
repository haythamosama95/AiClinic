import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/core/domain/clinic/staff_list_item.dart';
import 'package:ai_clinic/features/shifts/domain/shift_branch_staff.dart';
import 'package:ai_clinic/features/shifts/domain/shift_list_item.dart';

/// Doctors eligible for shift display — branch staff first, then org-wide fallback.
List<StaffListItem> resolveShiftDoctors({
  required List<ShiftBranchStaffMember> branchStaff,
  required List<ShiftListItem> shifts,
  required List<StaffListItem> fallbackStaff,
}) {
  final doctorsById = <String, StaffListItem>{};

  void addDoctor(ShiftBranchStaffMember member) {
    if (member.role != StaffRole.doctor) {
      return;
    }
    doctorsById[member.id] = StaffListItem(
      id: member.id,
      fullName: member.fullName,
      role: member.role,
      isActive: true,
    );
  }

  for (final member in branchStaff) {
    addDoctor(member);
  }

  final assigneeIds = <String>{
    for (final shift in shifts)
      for (final assigneeId in shift.assigneeIds)
        if (assigneeId.trim().isNotEmpty) assigneeId.trim(),
  };

  if (assigneeIds.isNotEmpty) {
    for (final member in branchStaff) {
      if (member.role == StaffRole.doctor && assigneeIds.contains(member.id)) {
        addDoctor(member);
      }
    }

    for (final member in fallbackStaff) {
      if (member.role != StaffRole.doctor || !member.isActive) {
        continue;
      }
      if (assigneeIds.contains(member.id)) {
        doctorsById.putIfAbsent(
          member.id,
          () => StaffListItem(id: member.id, fullName: member.fullName, role: member.role, isActive: member.isActive),
        );
      }
    }
  }

  if (doctorsById.isEmpty) {
    for (final member in branchStaff) {
      addDoctor(member);
    }
    if (doctorsById.isEmpty) {
      for (final member in fallbackStaff) {
        if (member.role == StaffRole.doctor && member.isActive) {
          doctorsById[member.id] = member;
        }
      }
    }
  }

  final doctors = doctorsById.values.toList(growable: false)..sort(StaffListItem.compareByFullName);
  return doctors;
}
