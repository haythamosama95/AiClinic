import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/features/appointments/presentation/providers/appointment_calendar_provider.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_detail_provider.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_detail_siblings_provider.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_queue_provider.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_shift_lookup_provider.dart';

/// Clears cached appointment queue/calendar state after clinic data is wiped or re-seeded.
void invalidateAllAppointmentSurfaces(Ref ref) {
  ref.invalidate(appointmentQueueProvider);
  ref.invalidate(appointmentCalendarProvider);
  ref.invalidate(appointmentShiftLookupProvider);
  ref.invalidate(appointmentCalendarBranchesProvider);
  ref.invalidate(appointmentCalendarDoctorsProvider);
}

/// Refreshes appointment surfaces affected by a status change or reschedule mutation.
void invalidateAppointmentAfterMutation(
  Ref ref, {
  required String appointmentId,
  required String branchId,
  required DateTime startTime,
}) {
  ref.invalidate(appointmentDetailProvider(appointmentId));
  ref.invalidate(
    appointmentDetailSiblingsProvider(
      AppointmentDetailSiblingsQuery(branchId: branchId, startTime: startTime),
    ),
  );
  ref.invalidate(
    appointmentShiftLookupProvider(
      AppointmentShiftLookupQuery(branchId: branchId, day: startTime),
    ),
  );
  ref.invalidate(appointmentCalendarProvider);
  ref.invalidate(appointmentQueueProvider);
}

/// Refreshes appointment surfaces after a visit is completed.
void invalidateAppointmentAfterVisitCompleted(
  Ref ref, {
  required String appointmentId,
  String? branchId,
  DateTime? startTime,
}) {
  if (branchId != null && startTime != null) {
    invalidateAppointmentAfterMutation(
      ref,
      appointmentId: appointmentId,
      branchId: branchId,
      startTime: startTime,
    );
    return;
  }

  ref.invalidate(appointmentDetailProvider(appointmentId));
  ref.invalidate(appointmentCalendarProvider);
  ref.invalidate(appointmentQueueProvider);
}

/// [WidgetRef] overload for presentation call sites that do not have a [Ref].
void invalidateAppointmentAfterMutationFromWidget(
  WidgetRef ref, {
  required String appointmentId,
  required String branchId,
  required DateTime startTime,
}) {
  ref.invalidate(appointmentDetailProvider(appointmentId));
  ref.invalidate(
    appointmentDetailSiblingsProvider(
      AppointmentDetailSiblingsQuery(branchId: branchId, startTime: startTime),
    ),
  );
  ref.invalidate(
    appointmentShiftLookupProvider(
      AppointmentShiftLookupQuery(branchId: branchId, day: startTime),
    ),
  );
  ref.invalidate(appointmentCalendarProvider);
  ref.invalidate(appointmentQueueProvider);
}
