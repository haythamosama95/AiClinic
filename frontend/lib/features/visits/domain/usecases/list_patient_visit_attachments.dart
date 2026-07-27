import 'package:ai_clinic/features/visits/data/visit_repository.dart';
import 'package:ai_clinic/features/visits/domain/patient_visit_document.dart';

class ListPatientVisitAttachments {
  const ListPatientVisitAttachments(this._repository);

  final VisitRepository _repository;

  Future<List<PatientVisitDocument>> call({required String patientId}) async {
    final rows = await _repository.listPatientVisitAttachments(patientId: patientId);
    return [
      for (final row in rows)
        PatientVisitDocument(visitId: row.visitId, visitDate: row.visitDate, attachment: row.attachment),
    ];
  }
}
