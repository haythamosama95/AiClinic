import 'package:ai_clinic/core/rpc/rpc_result.dart';

/// User-facing messages for organization RPC error codes.
String organizationMessageForRpc(RpcFailure failure) {
  return switch (failure.code) {
    'FORBIDDEN' => 'You do not have permission to update organization settings.',
    'ORG_NOT_FOUND' => 'Your clinic organization could not be found. Contact support.',
    'INVALID_INPUT' => failure.message,
    'RPC_NOT_APPLIED' => failure.message,
    _ => 'Unable to save organization settings. Check connectivity and try again.',
  };
}

/// User-facing messages for branch management RPC error codes.
String branchMessageForRpc(RpcFailure failure) {
  return switch (failure.code) {
    'LAST_ACTIVE_BRANCH' => failure.message,
    'DUPLICATE_CODE' => 'Another branch already uses this code. Choose a different code.',
    'FORBIDDEN' => 'You do not have permission to manage branches.',
    'BRANCH_NOT_FOUND' => 'That branch was not found. Refresh the list and try again.',
    'INVALID_INPUT' => failure.message,
    'RPC_NOT_APPLIED' => failure.message,
    _ => 'Unable to complete the branch action. Check connectivity and try again.',
  };
}

/// User-facing messages for staff management RPC error codes.
String staffMessageForRpc(RpcFailure failure) {
  return switch (failure.code) {
    'FORBIDDEN_OWNER_CREATE' => failure.message,
    'FORBIDDEN' => 'You do not have permission to manage staff.',
    'STAFF_NOT_FOUND' => 'That staff member was not found. Refresh the list and try again.',
    'CROSS_ORG_DENIED' => 'That staff member is outside your clinic organization.',
    'INVALID_BRANCH' => 'One or more selected branches are invalid or inactive.',
    'INVALID_INPUT' => failure.message,
    'RPC_NOT_APPLIED' => failure.message,
    _ => 'Unable to complete the staff action. Check connectivity and try again.',
  };
}
