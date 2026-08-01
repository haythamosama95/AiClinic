import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/setup/application/setup_rpc_messages.dart';
import 'package:flutter_test/flutter_test.dart';

RpcFailure _failure(String code, {String? message}) {
  return RpcFailure(
    RpcResult(success: false, errorCode: code, errorMessage: message),
  );
}

void main() {
  group('setup RPC messages', () {
    test('ORG_ALREADY_EXISTS', () {
      expect(
        setupMessageForRpc(_failure('ORG_ALREADY_EXISTS')),
        'An organization already exists for this installation.',
      );
    });

    test('NOT_BOOTSTRAP_ADMIN', () {
      expect(
        setupMessageForRpc(_failure('NOT_BOOTSTRAP_ADMIN')),
        'Only the clinic administrator account can run first-time setup.',
      );
    });

    test('ORG_NOT_FOUND', () {
      expect(
        setupMessageForRpc(_failure('ORG_NOT_FOUND')),
        'The organization could not be found. Restart setup from the beginning.',
      );
    });

    test('INVALID_INPUT surfaces server message', () {
      expect(
        setupMessageForRpc(_failure('INVALID_INPUT', message: 'Organization name is required.')),
        'Organization name is required.',
      );
    });

    test('RESET_INCOMPLETE', () {
      expect(
        setupMessageForRpc(_failure('RESET_INCOMPLETE')),
        'Clinic data could not be cleared. Apply the latest database migrations and try again.',
      );
    });

    test('RESET_NOT_APPLIED surfaces server message', () {
      expect(
        setupMessageForRpc(_failure('RESET_NOT_APPLIED', message: 'Reset was not applied.')),
        'Reset was not applied.',
      );
    });

    test('RESET_SAFE_DELETE surfaces server message', () {
      expect(
        setupMessageForRpc(_failure('RESET_SAFE_DELETE', message: 'Safe delete is required.')),
        'Safe delete is required.',
      );
    });

    test('RESET_DEPENDENCY_BLOCKED surfaces server message', () {
      expect(
        setupMessageForRpc(_failure('RESET_DEPENDENCY_BLOCKED', message: 'Dependent records remain.')),
        'Dependent records remain.',
      );
    });

    test('unknown code falls back to generic message', () {
      expect(
        setupMessageForRpc(_failure('UNKNOWN_CODE')),
        'Unable to save clinic setup. Check connectivity and try again.',
      );
    });
  });
}
