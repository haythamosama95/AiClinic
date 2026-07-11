import 'package:ai_clinic/core/rpc/rpc_result.dart';

/// User-facing messages for clinic setup RPC error codes.
String setupMessageForRpc(RpcFailure failure) {
  return switch (failure.code) {
    'ORG_ALREADY_EXISTS' => 'An organization already exists for this installation.',
    'NOT_BOOTSTRAP_ADMIN' => 'Only the clinic administrator account can run first-time setup.',
    'ORG_NOT_FOUND' => 'The organization could not be found. Restart setup from the beginning.',
    'INVALID_INPUT' => failure.message,
    'RESET_INCOMPLETE' => 'Clinic data could not be cleared. Apply the latest database migrations and try again.',
    'RESET_NOT_APPLIED' => failure.message,
    'RESET_SAFE_DELETE' => failure.message,
    'RESET_DEPENDENCY_BLOCKED' => failure.message,
    _ => 'Unable to save clinic setup. Check connectivity and try again.',
  };
}