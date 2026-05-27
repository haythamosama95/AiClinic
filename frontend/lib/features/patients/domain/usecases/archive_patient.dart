import 'package:ai_clinic/features/patients/domain/repositories/patient_repository.dart';

class ArchivePatient {
  const ArchivePatient(this._repository);
  final PatientRepository _repository;

  Future<void> call(String patientId) {
    return _repository.archivePatient(patientId);
  }
}
