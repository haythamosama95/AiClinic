import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/timezone.dart' as tz;

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_org_calendar.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_queue_shift_doctors.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_shift_doctor_resolution.dart';
import 'package:ai_clinic/features/clinic-management/domain/staff_list_filter.dart';
import 'package:ai_clinic/features/clinic-management/domain/usecases/clinic_management_use_case_providers.dart';
import 'package:ai_clinic/features/shifts/data/shift_repository.dart';

@immutable
class AppointmentShiftLookupQuery {
  const AppointmentShiftLookupQuery({required this.branchId, this.day});

  final String branchId;
  final DateTime? day;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is AppointmentShiftLookupQuery &&
            runtimeType == other.runtimeType &&
            branchId == other.branchId &&
            day == other.day;
  }

  @override
  int get hashCode => Object.hash(branchId, day);
}

/// Shift doctor lookup for a branch and day (`day == null` means today in org timezone).
final appointmentShiftLookupProvider = FutureProvider.autoDispose
    .family<AppointmentQueueShiftDoctorLookup, AppointmentShiftLookupQuery>((ref, query) async {
      final branchId = query.branchId.trim();
      if (branchId.isEmpty) {
        return AppointmentQueueShiftDoctorLookup.empty;
      }

      final timezone = effectiveOrganizationTimezone(
        ref.watch(authSessionProvider.select((session) => session.context?.organizationTimezone)),
      );
      ensureAppointmentTimezonesInitialized();
      final location = tz.getLocation(timezone);
      final source = query.day ?? DateTime.now().toUtc();
      final localStart = tz.TZDateTime.from(source.toUtc(), location);
      final appointmentDay = DateTime(localStart.year, localStart.month, localStart.day);

      final shiftRepository = ref.read(shiftRepositoryProvider);
      final shifts = await shiftRepository.listShifts(
        branchId: branchId,
        dateFrom: appointmentDay,
        dateTo: appointmentDay,
      );
      final branchStaff = await shiftRepository.listActiveStaffForBranch(branchId);
      final fallbackStaff = await ref.read(listStaffUseCaseProvider)(filter: StaffListFilter.active);

      final doctors = resolveShiftDoctors(branchStaff: branchStaff, shifts: shifts, fallbackStaff: fallbackStaff);

      return AppointmentQueueShiftDoctorLookup.fromShiftsAndDoctors(
        organizationTimezone: timezone,
        shifts: shifts,
        doctors: doctors,
      );
    });
