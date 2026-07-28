import 'package:ai_clinic/features/patients/domain/repositories/patient_repository.dart';

class ReassignPatientMrn {
  const ReassignPatientMrn(this._repository);
  final PatientRepository _repository;

  Future<String> call({required String patientId, required String newMrn}) {
    return _repository.reassignPatientMrn(patientId: patientId, newMrn: newMrn);
  }
}
