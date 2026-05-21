import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RpcResult', () {
    test('parses map-shaped PostgREST payload', () {
      final result = RpcResult.fromDynamic({
        'success': true,
        'data': {'organization_id': 'org-1'},
        'error_code': null,
        'error_message': null,
      });

      expect(result.success, isTrue);
      expect(result.data?['organization_id'], 'org-1');
    });

    test('parses composite list payload', () {
      final result = RpcResult.fromDynamic([false, null, 'ORG_ALREADY_EXISTS', 'An organization already exists']);

      expect(result.success, isFalse);
      expect(result.errorCode, 'ORG_ALREADY_EXISTS');
    });

    test('RpcFailure exposes code and message', () {
      final failure = RpcFailure(
        RpcResult.fromDynamic({
          'success': false,
          'error_code': 'INVALID_INPUT',
          'error_message': 'Organization name is required.',
        }),
      );

      expect(failure.code, 'INVALID_INPUT');
      expect(failure.message, contains('required'));
    });

    test('throws on unrecognized payload', () {
      expect(() => RpcResult.fromDynamic('nope'), throwsFormatException);
    });
  });
}
