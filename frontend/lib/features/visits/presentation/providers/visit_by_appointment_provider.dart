import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/features/visits/data/visit_repository.dart';

/// Visit linked to an appointment (`get_visit_by_appointment`).
final visitByAppointmentProvider = FutureProvider.autoDispose.family<VisitByAppointmentResult, String>((
  ref,
  appointmentId,
) {
  return ref.watch(visitRepositoryProvider).getVisitByAppointment(appointmentId: appointmentId);
});
