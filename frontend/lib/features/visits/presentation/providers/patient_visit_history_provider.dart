import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/features/visits/domain/patient_visit_document.dart';
import 'package:ai_clinic/features/visits/domain/usecases/visit_use_case_providers.dart';
import 'package:ai_clinic/features/visits/domain/visit_list_item.dart';

/// Past visits for a patient (`list_patient_visits`).
final patientPastVisitsProvider = FutureProvider.autoDispose.family<List<VisitListItem>, String>((
  ref,
  patientId,
) async {
  return ref.read(listPatientVisitsUseCaseProvider).call(patientId: patientId);
});

/// Visit attachments for a patient (`list_patient_visit_attachments`).
final patientVisitDocumentsProvider = FutureProvider.autoDispose.family<List<PatientVisitDocument>, String>((
  ref,
  patientId,
) async {
  return ref.read(listPatientVisitAttachmentsUseCaseProvider).call(patientId: patientId);
});
