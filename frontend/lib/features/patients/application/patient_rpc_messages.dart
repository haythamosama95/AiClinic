import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/l10n/app_localizations.dart';

/// User-facing copy for patient RPC failures (V1-3).
String patientMessageForRpc(RpcFailure failure, AppLocalizations l10n) {
  return switch (failure.code) {
    'NOT_FOUND' => l10n.patientRpcNotFound,
    'DUPLICATE_WARNING' => l10n.patientRpcDuplicateWarning,
    'STALE_PATIENT' => l10n.patientRpcStalePatient,
    'PATIENT_ARCHIVED' => l10n.patientRpcPatientArchived,
    'FORBIDDEN' => l10n.patientRpcForbidden,
    'BRANCH_REQUIRED' => l10n.patientRpcBranchRequired,
    'INVALID_INPUT' => failure.message,
    _ => failure.message.isNotEmpty ? failure.message : l10n.patientRpcDefaultError,
  };
}
