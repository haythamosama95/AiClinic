import 'package:ai_clinic/features/visits/data/visit_repository.dart';
import 'package:ai_clinic/features/visits/domain/visit_list_item.dart';

class ListPatientVisits {
  const ListPatientVisits(this._repository);

  final VisitRepository _repository;

  Future<List<VisitListItem>> call({required String patientId, int limit = 100}) async {
    final page = await _repository.listPatientVisits(patientId: patientId, limit: limit);
    final visits = [...page.items]..sort((a, b) => b.visitDate.compareTo(a.visitDate));
    return visits;
  }
}
