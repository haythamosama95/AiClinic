import 'package:ai_clinic/core/rpc/rpc_result.dart';

/// User-facing copy for appointment RPC failures (V1-4).
String appointmentMessageForRpc(RpcFailure failure) {
  return switch (failure.code) {
    'SCHEDULE_CONFLICT' => 'This time overlaps another booked slot. Choose a different slot.',
    'PATIENT_ALREADY_BOOKED_SAME_DAY' =>
      'This patient already has an appointment on the same day. Update the existing appointment instead.',
    'INVALID_TRANSITION' => switch (failure.message.toLowerCase()) {
      final message when message.contains('appointment day') =>
        'This status change is only allowed on or after the appointment day.',
      _ => 'That status change is not allowed for this appointment.',
    },
    'PATIENT_ARCHIVED' => 'This patient is archived and cannot be booked.',
    'INVALID_DOCTOR' => 'The selected doctor is not available at this branch.',
    'RPC_NOT_CONFIGURED' =>
      'Appointment database permissions are incomplete. Ask your administrator to run the latest Supabase migrations.',
    'RPC_NOT_APPLIED' =>
      'Appointment scheduling is not installed on this database. Ask your administrator to run Supabase migrations.',
    'FORBIDDEN' => 'You do not have permission to perform this action.',
    'INVALID_INPUT' => failure.message,
    _ => failure.message,
  };
}
