import 'package:ai_clinic/core/rpc/rpc_result.dart';

import 'clinical_acceptance_port.dart';

/// Clinical accept path for demonstration target [visit_clinical_notes].
///
/// Accept invokes [ClinicalAcceptancePort.recordAcceptance]; discard writes nothing.
class ClinicalAcceptController {
  ClinicalAcceptController({required ClinicalAcceptancePort port}) : _port = port;

  final ClinicalAcceptancePort _port;

  static const demonstrationTargetKey = 'visit_clinical_notes';

  /// Explicit human accept — records acceptance with the retained request reference.
  Future<RpcResult> acceptVisitClinicalNotes({
    required String requestReference,
    required String visitId,
    required String complaint,
    required DateTime expectedUpdatedAt,
    String? history,
    String? examination,
    String? diagnosis,
    String? plan,
  }) {
    return _port.recordAcceptance(
      requestReference: requestReference,
      targetKey: demonstrationTargetKey,
      targetArgs: {
        'p_visit_id': visitId,
        'p_complaint': complaint,
        'p_history': ?history,
        'p_examination': ?examination,
        'p_diagnosis': ?diagnosis,
        'p_plan': ?plan,
        'p_expected_updated_at': expectedUpdatedAt.toUtc().toIso8601String(),
      },
    );
  }

  /// Discard clears the accept path without writing anything.
  void discard() {}
}
