import 'package:ai_clinic/features/patients/domain/repositories/patient_repository.dart';
import 'package:ai_clinic/features/patients/domain/update_patient_input.dart';

class UpdatePatient {
  const UpdatePatient(this._repository);
  final PatientRepository _repository;

  Future<DateTime> call(UpdatePatientInput input) {
    return _repository.updatePatient(input);
  }
}
