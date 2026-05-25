import 'package:ai_clinic/features/patients/domain/create_patient_input.dart';
import 'package:ai_clinic/features/patients/domain/repositories/patient_repository.dart';

class CreatePatient {
  const CreatePatient(this._repository);
  final PatientRepository _repository;

  Future<String> call(CreatePatientInput input) {
    return _repository.createPatient(input);
  }
}
