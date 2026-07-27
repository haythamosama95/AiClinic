import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/patients/domain/duplicate_candidate.dart';

/// Parses `candidates` from RPC success or `DUPLICATE_WARNING` error payloads.
List<DuplicateCandidate> parseDuplicateCandidates(Object? raw) {
  if (raw is! List) {
    return const [];
  }

  final candidates = <DuplicateCandidate>[];
  for (final entry in raw) {
    if (entry is Map) {
      final candidate = DuplicateCandidate.fromRow(Map<String, dynamic>.from(entry));
      if (candidate != null) {
        candidates.add(candidate);
      }
    }
  }
  return candidates;
}

/// Patient-specific interpretation of [RpcFailure] from create/update/check RPCs.
extension PatientRpcFailure on RpcFailure {
  bool get isDuplicateWarning => code == 'DUPLICATE_WARNING';

  bool get isStalePatient => code == 'STALE_PATIENT';

  List<DuplicateCandidate> get duplicateCandidates =>
      parseDuplicateCandidates(result.data?['candidates']);
}
