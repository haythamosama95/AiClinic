import 'package:ai_clinic/core/rpc/rpc_result.dart';

/// User-facing messages for provisioning RPC error codes.
///
/// Shared by the setup wizard's bootstrap path (which can surface provisioning
/// error codes like `USERNAME_EXISTS`/`WEAK_PASSWORD` from `bootstrap_finish_setup`)
/// and the settings staff-management notifier. Lives in the setup application
/// layer so both the bootstrap feature and the settings feature can import it
/// without a cross-feature notifier dependency (review §6.2/§6.5).
String provisioningMessageForRpc(RpcFailure failure) {
  return switch (failure.code) {
    'ORG_SETUP_INCOMPLETE' => 'Create your clinic organization and first branch before adding staff accounts.',
    'FORBIDDEN' => 'You do not have permission to create staff accounts.',
    'USERNAME_EXISTS' => 'A staff account with this username already exists.',
    'INVALID_BRANCH' => 'One or more selected branches are invalid.',
    'INVALID_INPUT' => failure.message,
    'WEAK_PASSWORD' => failure.message,
    'RPC_NOT_APPLIED' => failure.message,
    _ => 'Unable to create the staff account. Check connectivity and try again.',
  };
}

/// User-facing messages for password-reset RPC error codes.
String passwordResetMessageForRpc(RpcFailure failure) {
  return switch (failure.code) {
    'FORBIDDEN' => 'You do not have permission to reset staff passwords.',
    'STAFF_NOT_FOUND' => 'That staff member was not found. Refresh the list and try again.',
    'CROSS_ORG_DENIED' => 'That staff member is outside your clinic organization.',
    'INVALID_INPUT' => failure.message,
    'WEAK_PASSWORD' => failure.message,
    'RPC_NOT_APPLIED' => failure.message,
    _ => 'Unable to reset the password. Check connectivity and try again.',
  };
}

/// User-facing messages for username-update RPC error codes.
String usernameUpdateMessageForRpc(RpcFailure failure) {
  return switch (failure.code) {
    'FORBIDDEN' => 'You do not have permission to change staff usernames.',
    'STAFF_NOT_FOUND' => 'That staff member was not found. Refresh the list and try again.',
    'CROSS_ORG_DENIED' => 'That staff member is outside your clinic organization.',
    'USERNAME_EXISTS' => 'A staff account with this username already exists.',
    'INVALID_INPUT' => failure.message,
    'RPC_NOT_APPLIED' => failure.message,
    _ => 'Unable to update the username. Check connectivity and try again.',
  };
}
