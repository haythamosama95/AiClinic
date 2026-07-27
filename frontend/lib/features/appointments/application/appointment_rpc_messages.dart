import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/utils/user_error_mapper.dart';

/// User-facing copy for appointment RPC failures (V1-4).
String appointmentMessageForRpc(RpcFailure failure) {
  return switch (failure.code) {
    'SCHEDULE_CONFLICT' => 'This time overlaps another booked slot. Choose a different slot.',
    'PATIENT_ALREADY_BOOKED_SAME_DAY' =>
      'This patient already has an appointment on the same day. Update the existing appointment instead.',
    'DOCTOR_ALREADY_IN_PROGRESS' =>
      'This doctor already has a patient in progress. Complete that visit before starting another.',
    'VISIT_IN_PROGRESS' => 'Cannot undo while a visit exists for this appointment. Complete or cancel the visit first.',
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
    'PERMISSION_DENIED' => 'You do not have permission to view this appointment.',
    'NOT_FOUND' => switch (failure.message.toLowerCase()) {
      final message when message.contains('patient') => 'Patient was not found.',
      final message when message.contains('appointment') => 'Appointment was not found.',
      _ => 'The requested record was not found.',
    },
    'INVALID_BRANCH' => 'The selected branch is not valid for this session.',
    'INVALID_INPUT' => switch (failure.message) {
      'branch_id_required' => 'Branch id is required.',
      'notes_too_long' => 'Notes must be 2000 characters or fewer.',
      'start_time_required' => 'Start time is required for appointments.',
      'cancel_reason_too_long' => 'Cancel reason must be 2000 characters or fewer.',
      'field_required' => 'A required field is missing.',
      'duration_below_minimum' => 'Duration must be at least 5 minutes.',
      'range_end_before_start' => 'End of range must be after the start.',
      _ => failure.message,
    },
    _ => failure.message,
  };
}

/// Single entry point for appointment error text shown in the UI.
String appointmentMessageForError(Object error) {
  if (error is RpcFailure) {
    return appointmentMessageForRpc(error);
  }
  return UserErrorMapper.mapToUserMessage(error);
}
