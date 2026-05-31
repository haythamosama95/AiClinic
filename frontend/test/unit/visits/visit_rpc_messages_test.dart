import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/visits/presentation/visit_rpc_messages.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
