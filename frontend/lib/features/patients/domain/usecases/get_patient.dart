import 'package:ai_clinic/features/patients/domain/patient_detail.dart';
import 'package:ai_clinic/features/patients/domain/repositories/patient_repository.dart';

class GetPatient {
  const GetPatient(this._repository);
  final PatientRepository _repository;

  Future<PatientDetail> call(String patientId) {
    return _repository.getPatient(patientId);
  }
}
