import 'package:ai_clinic/core/rpc/rpc_result.dart';

/// User-facing copy for shift RPC failures (V1-7).
String shiftMessageForRpc(RpcFailure failure) {
  return switch (failure.code) {
    'shift_overlap' => 'One or more staff members already have an overlapping shift at this branch.',
    'staff_not_eligible' => 'A selected staff member is inactive or not assigned to this branch.',
    'shift_invalid_time_range' => 'End time must be after start time.',
    'shift_read_only_past_date' => 'Only today and future dates may be scheduled.',
    'notes_too_long' => 'Notes must be 500 characters or fewer.',
    'permission_denied' => 'You do not have permission to manage shifts.',
    'RPC_NOT_CONFIGURED' =>
      'Shift database permissions are incomplete. Ask your administrator to run the latest Supabase migrations.',
    'RPC_NOT_APPLIED' =>
      'Shift management is not installed on this database. Ask your administrator to run Supabase migrations.',
    _ => failure.message,
  };
}
