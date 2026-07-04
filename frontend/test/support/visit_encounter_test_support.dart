import 'package:ai_clinic/features/visits/domain/visit_detail.dart';
import 'package:ai_clinic/features/visits/domain/visit_status.dart';
import 'package:ai_clinic/features/visits/domain/visit_vital_sign.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';

const encounterTestVisitId = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
const encounterTestPatientId = '11111111-1111-4111-8111-111111111111';
const encounterTestBranchId = '44444444-4444-4444-8444-444444444444';

VisitDetail sampleEncounterVisit({String? visitType, List<VisitVitalSign> vitalSigns = const []}) {
  return VisitDetail(
    id: encounterTestVisitId,
    branchId: encounterTestBranchId,
    appointmentId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    patientId: encounterTestPatientId,
    doctorId: 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
    doctorName: 'Dr Test',
    visitDate: DateTime.utc(2026, 5, 31),
    status: VisitStatus.inProgress,
    visitType: visitType,
    updatedAt: DateTime.utc(2026, 5, 31, 10),
    vitalSigns: vitalSigns,
  );
}

VisitDocumentationState sampleEncounterDocState({VisitDetail? visit}) {
  final resolved = visit ?? sampleEncounterVisit();
  return VisitDocumentationState(
    visit: resolved,
    persistedVisit: resolved,
    complaint: '',
    history: '',
    examination: '',
    diagnosis: '',
    plan: '',
    expectedUpdatedAt: resolved.updatedAt ?? resolved.visitDate,
    predefinedVitalSigns: const [],
  );
}
