import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/visits/data/visit_attachment_service.dart';
import 'package:ai_clinic/features/visits/application/visit_rpc_messages.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show StorageException;

void main() {
  group('visitMessageForRpc', () {
    test('maps known visit domain codes', () {
      expect(
        visitMessageForRpc(RpcFailure(const RpcResult(success: false, errorCode: 'STALE_SOAP', errorMessage: ''))),
        contains('updated elsewhere'),
      );
      expect(
        visitMessageForRpc(
          RpcFailure(const RpcResult(success: false, errorCode: 'VISIT_REQUIRED_FOR_COMPLETION', errorMessage: '')),
        ),
        contains('visit documentation'),
      );
      expect(
        visitMessageForRpc(
          RpcFailure(const RpcResult(success: false, errorCode: 'ATTACHMENT_DOWNLOAD_DENIED', errorMessage: '')),
        ),
        contains('you uploaded'),
      );
    });

    test('falls back to server message for unknown codes', () {
      expect(
        visitMessageForRpc(
          RpcFailure(const RpcResult(success: false, errorCode: 'CUSTOM', errorMessage: 'Server detail.')),
        ),
        'Server detail.',
      );
    });
  });

  group('visitMessageForUploadError', () {
    test('maps storage RLS errors to a friendly permission message', () {
      expect(
        visitMessageForUploadError(const StorageException('new row violates row level security policy')),
        isNot(contains('StorageException')),
      );
      expect(
        visitMessageForUploadError(const StorageException('new row violates row level security policy')),
        contains('permission'),
      );
    });

    test('maps validation and RPC errors', () {
      expect(
        visitMessageForUploadError(
          const VisitAttachmentValidationException('Only PDF allowed.', errorCode: 'INVALID_FILE_TYPE'),
        ),
        'Only PDF allowed.',
      );
      expect(
        visitMessageForUploadError(
          RpcFailure(const RpcResult(success: false, errorCode: 'FORBIDDEN', errorMessage: 'denied')),
        ),
        contains('permission'),
      );
    });

    test('uses generic message for unknown upload failures', () {
      expect(visitMessageForUploadError(StateError('boom')), contains('Could not upload'));
    });
  });

  group('visitMessageForDownloadError', () {
    test('maps HTTP download StateError without upload wording', () {
      expect(
        visitMessageForDownloadError(StateError('Could not download the file (404)')),
        'Could not download the file (404).',
      );
      expect(visitMessageForDownloadError(StateError('Could not download the file (404)')), isNot(contains('upload')));
    });

    test('maps RPC failures including download denied', () {
      expect(
        visitMessageForDownloadError(
          RpcFailure(const RpcResult(success: false, errorCode: 'ATTACHMENT_DOWNLOAD_DENIED', errorMessage: '')),
        ),
        contains('you uploaded'),
      );
    });

    test('uses generic message for unknown download failures', () {
      expect(visitMessageForDownloadError(Exception('save failed')), contains('Could not download'));
      expect(visitMessageForDownloadError(Exception('save failed')), isNot(contains('upload')));
    });

    test('maps storage not found for download', () {
      expect(visitMessageForDownloadError(const StorageException('Object not found')), contains('could not be found'));
    });
  });
}
