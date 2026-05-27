import 'package:ai_clinic/features/patients/domain/patient_list_scope.dart';
import 'package:ai_clinic/features/patients/domain/patient_search_page.dart';
import 'package:ai_clinic/features/patients/domain/repositories/patient_repository.dart';

class SearchPatients {
  const SearchPatients(this._repository);
  final PatientRepository _repository;

  Future<PatientSearchPage> call({
    String? query,
    required PatientListScope scope,
    String? branchId,
    int limit = 25,
    int offset = 0,
  }) {
    return _repository.searchPatients(
      query: query,
      scope: scope,
      branchId: branchId,
      limit: limit,
      offset: offset,
    );
  }
}
