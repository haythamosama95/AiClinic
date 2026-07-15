import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/features/appointments/presentation/providers/appointment_calendar_provider.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_queue_provider.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_queue_shift_provider.dart';

/// Clears cached appointment queue/calendar state after clinic data is wiped or re-seeded.
void invalidateAppointmentSurfaceProviders(Ref ref) {
  ref.invalidate(appointmentQueueProvider);
  ref.invalidate(appointmentCalendarProvider);
  ref.invalidate(appointmentQueueShiftDoctorLookupProvider);
  ref.invalidate(appointmentCalendarBranchesProvider);
  ref.invalidate(appointmentCalendarDoctorsProvider);
}
