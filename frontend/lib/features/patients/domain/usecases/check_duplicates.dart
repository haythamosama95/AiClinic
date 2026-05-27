import 'package:ai_clinic/features/patients/domain/duplicate_candidate.dart';
import 'package:ai_clinic/features/patients/domain/repositories/patient_repository.dart';

class CheckDuplicates {
  const CheckDuplicates(this._repository);
  final PatientRepository _repository;

  Future<List<DuplicateCandidate>> call({
    String? fullName,
    String? phone,
    DateTime? dateOfBirth,
    String? excludePatientId,
  }) {
    return _repository.checkDuplicates(
      fullName: fullName,
      phone: phone,
      dateOfBirth: dateOfBirth,
      excludePatientId: excludePatientId,
    );
  }
}
