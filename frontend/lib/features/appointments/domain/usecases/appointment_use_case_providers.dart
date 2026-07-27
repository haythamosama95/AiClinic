import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/appointments/domain/usecases/list_patient_upcoming_appointments.dart';

final listPatientUpcomingAppointmentsUseCaseProvider = Provider(
  (ref) => ListPatientUpcomingAppointments(ref.watch(appointmentRepositoryProvider)),
);
