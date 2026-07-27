import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/features/visits/data/visit_repository.dart';
import 'package:ai_clinic/features/visits/domain/usecases/list_patient_visits.dart';
import 'package:ai_clinic/features/visits/domain/usecases/list_patient_visit_attachments.dart';

final listPatientVisitsUseCaseProvider = Provider(
  (ref) => ListPatientVisits(ref.watch(visitRepositoryProvider)),
);

final listPatientVisitAttachmentsUseCaseProvider = Provider(
  (ref) => ListPatientVisitAttachments(ref.watch(visitRepositoryProvider)),
);
