import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/timezone.dart' as tz;

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_org_calendar.dart';
import 'package:ai_clinic/features/queue/domain/queue_shift_doctors.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_queue_shift_provider.dart';
import 'package:ai_clinic/features/clinic-management/domain/staff_list_filter.dart';
import 'package:ai_clinic/features/clinic-management/domain/usecases/clinic_management_use_case_providers.dart';
import 'package:ai_clinic/features/shifts/data/shift_repository.dart';

@immutable
class AppointmentDetailShiftQuery {
  const AppointmentDetailShiftQuery({
    required this.branchId,
    required this.appointmentStart,
  });

  final String branchId;
  final DateTime appointmentStart;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is AppointmentDetailShiftQuery &&
            runtimeType == other.runtimeType &&
            branchId == other.branchId &&
            appointmentStart == other.appointmentStart;
  }

  @override
  int get hashCode => Object.hash(branchId, appointmentStart);
}

/// Shift doctor lookup for a specific appointment branch and day.
final appointmentDetailShiftLookupProvider = FutureProvider.autoDispose
    .family<AppointmentQueueShiftDoctorLookup, AppointmentDetailShiftQuery>((
      ref,
      query,
    ) async {
      final branchId = query.branchId.trim();
      if (branchId.isEmpty) {
        return AppointmentQueueShiftDoctorLookup.empty;
      }

      final timezone = effectiveOrganizationTimezone(
        ref.read(authSessionProvider).context?.organizationTimezone,
      );
      ensureAppointmentTimezonesInitialized();
      final location = tz.getLocation(timezone);
      final localStart = tz.TZDateTime.from(
        query.appointmentStart.toUtc(),
        location,
      );
      final appointmentDay = DateTime(
        localStart.year,
        localStart.month,
        localStart.day,
      );

      final shiftRepository = ref.read(shiftRepositoryProvider);
      final shifts = await shiftRepository.listShifts(
        branchId: branchId,
        dateFrom: appointmentDay,
        dateTo: appointmentDay,
      );
      final branchStaff = await shiftRepository.listActiveStaffForBranch(
        branchId,
      );
      final fallbackStaff = await ref.read(listStaffUseCaseProvider)(
        filter: StaffListFilter.active,
      );

      final doctors = resolveQueueShiftDoctors(
        branchStaff: branchStaff,
        shifts: shifts,
        fallbackStaff: fallbackStaff,
      );

      return AppointmentQueueShiftDoctorLookup.fromShiftsAndDoctors(
        organizationTimezone: timezone,
        shifts: shifts,
        doctors: doctors,
      );
    });
