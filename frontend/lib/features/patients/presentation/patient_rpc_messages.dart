import 'package:ai_clinic/core/rpc/rpc_result.dart';

/// User-facing copy for patient RPC failures (V1-3).
String patientMessageForRpc(RpcFailure failure) {
  return switch (failure.code) {
    'NOT_FOUND' => 'Patient was not found or you do not have access.',
    'DUPLICATE_WARNING' => 'Similar patients were found. Review the list before continuing.',
    'STALE_PATIENT' => 'This record was updated elsewhere. Reload and try again.',
    'PATIENT_ARCHIVED' => 'This patient is archived and is not available.',
    'FORBIDDEN' => 'You do not have permission to perform this action.',
    'BRANCH_REQUIRED' => 'Select an active branch before registering a patient.',
    'INVALID_INPUT' => failure.message,
    _ => failure.message,
  };
}
