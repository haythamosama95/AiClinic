import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/timezone.dart' as tz;

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_org_calendar.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_queue_shift_doctors.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_filter.dart';
import 'package:ai_clinic/features/settings/domain/usecases/settings_use_case_providers.dart';
import 'package:ai_clinic/features/shifts/data/shift_repository.dart';

/// Shift doctor lookup for today's queue appointments card.
final appointmentQueueShiftDoctorLookupProvider = FutureProvider.autoDispose<AppointmentQueueShiftDoctorLookup>((
  ref,
) async {
  final auth = ref.watch(authSessionProvider).context;
  final branchId = auth?.activeBranchId?.trim();
  if (branchId == null || branchId.isEmpty) {
    return AppointmentQueueShiftDoctorLookup.empty;
  }

  final organizationTimezone = effectiveOrganizationTimezone(auth?.organizationTimezone);
  ensureAppointmentTimezonesInitialized();
  final location = tz.getLocation(organizationTimezone);
  final localNow = tz.TZDateTime.from(DateTime.now().toUtc(), location);
  final today = DateTime(localNow.year, localNow.month, localNow.day);

  final shifts = await ref.read(shiftRepositoryProvider).listShifts(branchId: branchId, dateFrom: today, dateTo: today);

  final staff = await ref.read(listStaffUseCaseProvider)(filter: StaffListFilter.active);
  final branchDoctors = staff
      .where((member) => member.role == StaffRole.doctor && member.isAssignedToBranch(branchId))
      .toList(growable: false);

  return AppointmentQueueShiftDoctorLookup.fromShiftsAndDoctors(
    organizationTimezone: organizationTimezone,
    shifts: shifts,
    doctors: branchDoctors,
  );
});
