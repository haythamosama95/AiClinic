import 'package:ai_clinic/core/rpc/rpc_result.dart';

/// User-facing copy for visit RPC failures (V1-5).
String visitMessageForRpc(RpcFailure failure) {
  return switch (failure.code) {
    'STALE_SOAP' => 'This visit note was updated elsewhere. Reload and try again.',
    'APPOINTMENT_NOT_ELIGIBLE' => 'Visits can only be started from checked-in or in-progress appointments.',
    'VISIT_ALREADY_EXISTS' => 'A visit already exists for this appointment. Open the existing visit instead.',
    'DOCTOR_REQUIRED' => 'Select a doctor before starting this visit.',
    'INVALID_DOCTOR' => 'The selected doctor is not available at this branch.',
    'SOAP_REQUIRED_FOR_COMPLETE' =>
      'Enter at least one SOAP section (subjective, objective, assessment, or plan) before submitting the visit.',
    'APPOINTMENT_NOT_IN_PROGRESS' => 'The linked appointment is no longer in progress. Reload the visit and try again.',
    'VISIT_REQUIRED_FOR_COMPLETION' => 'Complete the visit documentation to finish this appointment.',
    'INVALID_FILE_TYPE' => 'Only PDF, Word (DOCX), JPEG, and PNG files are allowed.',
    'FILE_TOO_LARGE' => 'Each attachment must be 25 MB or smaller.',
    'ATTACHMENT_DOWNLOAD_DENIED' => 'You can only download attachments you uploaded.',
    'RPC_NOT_CONFIGURED' =>
      'Visit database permissions are incomplete. Ask your administrator to run the latest Supabase migrations.',
    'RPC_NOT_APPLIED' =>
      'Visit medical records are not installed on this database. Ask your administrator to run Supabase migrations.',
    'FORBIDDEN' => 'You do not have permission to perform this action.',
    'NOT_FOUND' => failure.message,
    'INVALID_INPUT' =>
      failure.message.contains('Specialty')
          ? 'Specialty form data is not valid. Check required fields and try again.'
          : failure.message,
    _ => failure.message,
  };
}
