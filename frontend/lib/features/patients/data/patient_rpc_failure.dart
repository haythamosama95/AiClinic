import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/patients/data/patient_repository.dart';
import 'package:ai_clinic/features/patients/domain/duplicate_candidate.dart';

/// Patient-specific interpretation of [RpcFailure] from create/update/check RPCs.
extension PatientRpcFailure on RpcFailure {
  bool get isDuplicateWarning => code == 'DUPLICATE_WARNING';

  bool get isStalePatient => code == 'STALE_PATIENT';

  List<DuplicateCandidate> get duplicateCandidates =>
      PatientRepository.parseDuplicateCandidates(result.data?['candidates']);
}
