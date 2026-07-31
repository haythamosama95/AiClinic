import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/timezone.dart' as tz;

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_org_calendar.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_queue_shift_doctors.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/clinic-management/domain/staff_list_filter.dart';
import 'package:ai_clinic/features/clinic-management/domain/staff_list_item.dart';
import 'package:ai_clinic/features/clinic-management/domain/usecases/clinic_management_use_case_providers.dart';
import 'package:ai_clinic/features/shifts/data/shift_repository.dart';
import 'package:ai_clinic/features/shifts/domain/shift_branch_staff.dart';
import 'package:ai_clinic/features/shifts/domain/shift_list_item.dart';

/// Shift doctor lookup for today's queue appointments card.
final appointmentQueueShiftDoctorLookupProvider =
    FutureProvider.autoDispose<AppointmentQueueShiftDoctorLookup>((ref) async {
      final scope = ref.watch(
        authSessionProvider.select(
          (session) => (
            branchId: session.context?.activeBranchId?.trim() ?? '',
            organizationTimezone: effectiveOrganizationTimezone(
              session.context?.organizationTimezone,
            ),
          ),
        ),
      );
      if (scope.branchId.isEmpty) {
        return AppointmentQueueShiftDoctorLookup.empty;
      }

      ensureAppointmentTimezonesInitialized();
      final location = tz.getLocation(scope.organizationTimezone);
      final localNow = tz.TZDateTime.from(DateTime.now().toUtc(), location);
      final today = DateTime(localNow.year, localNow.month, localNow.day);

      final shiftRepository = ref.read(shiftRepositoryProvider);
      final shifts = await shiftRepository.listShifts(
        branchId: scope.branchId,
        dateFrom: today,
        dateTo: today,
      );
      final branchStaff = await shiftRepository.listActiveStaffForBranch(
        scope.branchId,
      );

      final doctors = resolveQueueShiftDoctors(
        branchStaff: branchStaff,
        shifts: shifts,
        fallbackStaff: await ref.read(listStaffUseCaseProvider)(
          filter: StaffListFilter.active,
        ),
      );

      return AppointmentQueueShiftDoctorLookup.fromShiftsAndDoctors(
        organizationTimezone: scope.organizationTimezone,
        shifts: shifts,
        doctors: doctors,
      );
    });

/// Doctors eligible for shift display — branch staff first, then org-wide fallback.
List<StaffListItem> resolveQueueShiftDoctors({
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

  // Match doctor assignees on today's shifts even when branch membership is missing.
  final assigneeKeys = <String>{};
  for (final shift in shifts) {
    for (final assignee in shift.assigneeNames) {
      final key = assignee.trim().toLowerCase();
      if (key.isNotEmpty) {
        assigneeKeys.add(key);
      }
    }
  }

  if (assigneeKeys.isNotEmpty) {
    for (final member in branchStaff) {
      if (member.role == StaffRole.doctor &&
          assigneeKeys.contains(member.fullName.toLowerCase())) {
        addDoctor(member);
      }
    }

    for (final member in fallbackStaff) {
      if (member.role != StaffRole.doctor || !member.isActive) {
        continue;
      }
      if (assigneeKeys.contains(member.fullName.toLowerCase())) {
        doctorsById.putIfAbsent(
          member.id,
          () => StaffListItem(
            id: member.id,
            fullName: member.fullName,
            role: member.role,
            isActive: member.isActive,
          ),
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

  final doctors = doctorsById.values.toList(growable: false)
    ..sort(StaffListItem.compareByFullName);
  return doctors;
}
