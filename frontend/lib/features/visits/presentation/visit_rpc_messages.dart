import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/visits/data/visit_attachment_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show StorageException;

/// User-facing copy for visit attachment upload failures (V1-5).
String visitMessageForUploadError(Object error) {
  if (error is VisitAttachmentValidationException) {
    return error.message;
  }
  if (error is RpcFailure) {
    return visitMessageForRpc(error);
  }
  if (error is StorageException) {
    final message = error.message.toLowerCase();
    if (message.contains('row level security') || message.contains('row-level security')) {
      return 'You do not have permission to upload attachments to this visit. '
          'If you work at multiple branches, sign out and sign in again, or ask your clinic administrator for access.';
    }
    if (message.contains('payload too large') || message.contains('file size') || message.contains('too large')) {
      return 'Each attachment must be 25 MB or smaller.';
    }
    if (message.contains('mime') || message.contains('content type')) {
      return 'Only PDF, Word (DOCX), JPEG, and PNG files are allowed.';
    }
    if (message.contains('already exists') || message.contains('duplicate')) {
      return 'An attachment with this name already exists. Rename the file and try again.';
    }
    return 'Could not upload the attachment. Please try again.';
  }
  return 'Could not upload the attachment. Please try again.';
}

/// User-facing copy for visit attachment download failures (V1-5).
String visitMessageForDownloadError(Object error) {
  if (error is RpcFailure) {
    return visitMessageForRpc(error);
  }
  if (error is StorageException) {
    final message = error.message.toLowerCase();
    if (message.contains('row level security') || message.contains('row-level security')) {
      return 'You do not have permission to download this attachment.';
    }
    if (message.contains('not found') || message.contains('object not found')) {
      return 'This attachment file could not be found. It may have been removed.';
    }
    return 'Could not download the attachment. Please try again.';
  }
  if (error is StateError) {
    final message = error.message.trim();
    if (message.contains('Download URL was invalid') || message.contains('Could not download')) {
      return message.endsWith('.') ? message : '$message.';
    }
  }
  return 'Could not download the attachment. Please try again.';
}

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
