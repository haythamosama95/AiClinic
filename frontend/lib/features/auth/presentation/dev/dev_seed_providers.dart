import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/repository_providers.dart';
import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/appointments/data/doctor_dev_seed_service.dart';
import 'package:ai_clinic/features/auth/data/provisioning_repository.dart';
import 'package:ai_clinic/features/auth/presentation/dev/appointment_dev_seed_service.dart';
import 'package:ai_clinic/features/patients/data/patient_dev_seed_service.dart';
import 'package:ai_clinic/features/patients/domain/usecases/patient_use_case_providers.dart';
import 'package:ai_clinic/features/settings/domain/usecases/settings_use_case_providers.dart';

final doctorDevSeedServiceProvider = Provider<DoctorDevSeedService>((ref) {
  return DoctorDevSeedService(
    staffAdmin: ref.watch(staffAdminRepositoryProvider),
    provisioning: ref.watch(provisioningRepositoryProvider),
  );
});

final patientDevSeedServiceProvider = Provider<PatientDevSeedService>((ref) {
  return PatientDevSeedService(
    patients: ref.watch(patientRepositoryProvider),
    branches: ref.watch(branchRepositoryProvider),
    staffAdmin: ref.watch(staffAdminRepositoryProvider),
  );
});

final appointmentDevSeedServiceProvider = Provider<AppointmentDevSeedService>((ref) {
  return AppointmentDevSeedService(
    appointments: ref.watch(appointmentRepositoryProvider),
    searchPatients: ref.watch(searchPatientsUseCaseProvider),
    listStaff: ref.watch(listStaffUseCaseProvider),
    branches: ref.watch(branchRepositoryProvider),
  );
});
