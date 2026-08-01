import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/setup/application/provisioning_rpc_messages.dart';
import 'package:flutter_test/flutter_test.dart';

RpcFailure _failure(String code, {String? message}) {
  return RpcFailure(
    RpcResult(success: false, errorCode: code, errorMessage: message),
  );
}

void main() {
  group('provisioningMessageForRpc', () {
    test('ORG_SETUP_INCOMPLETE', () {
      expect(
        provisioningMessageForRpc(_failure('ORG_SETUP_INCOMPLETE')),
        'Create your clinic organization and first branch before adding staff accounts.',
      );
    });

    test('FORBIDDEN', () {
      expect(
        provisioningMessageForRpc(_failure('FORBIDDEN')),
        'You do not have permission to create staff accounts.',
      );
    });

    test('USERNAME_EXISTS', () {
      expect(
        provisioningMessageForRpc(_failure('USERNAME_EXISTS')),
        'A staff account with this username already exists.',
      );
    });

    test('INVALID_BRANCH', () {
      expect(
        provisioningMessageForRpc(_failure('INVALID_BRANCH')),
        'One or more selected branches are invalid.',
      );
    });

    test('INVALID_INPUT surfaces server message', () {
      expect(
        provisioningMessageForRpc(_failure('INVALID_INPUT', message: 'Username is required.')),
        'Username is required.',
      );
    });

    test('WEAK_PASSWORD surfaces server message', () {
      expect(
        provisioningMessageForRpc(_failure('WEAK_PASSWORD', message: 'Password must contain at least one letter')),
        'Password must contain at least one letter',
      );
    });

    test('RPC_NOT_APPLIED surfaces server message', () {
      expect(
        provisioningMessageForRpc(_failure('RPC_NOT_APPLIED', message: 'Provisioning was not applied.')),
        'Provisioning was not applied.',
      );
    });

    test('unknown code falls back to generic message', () {
      expect(
        provisioningMessageForRpc(_failure('UNKNOWN_CODE')),
        'Unable to create the staff account. Check connectivity and try again.',
      );
    });
  });

  group('passwordResetMessageForRpc', () {
    test('FORBIDDEN', () {
      expect(
        passwordResetMessageForRpc(_failure('FORBIDDEN')),
        'You do not have permission to reset staff passwords.',
      );
    });

    test('STAFF_NOT_FOUND', () {
      expect(
        passwordResetMessageForRpc(_failure('STAFF_NOT_FOUND')),
        'That staff member was not found. Refresh the list and try again.',
      );
    });

    test('CROSS_ORG_DENIED', () {
      expect(
        passwordResetMessageForRpc(_failure('CROSS_ORG_DENIED')),
        'That staff member is outside your clinic organization.',
      );
    });

    test('INVALID_INPUT surfaces server message', () {
      expect(
        passwordResetMessageForRpc(_failure('INVALID_INPUT', message: 'Password is required.')),
        'Password is required.',
      );
    });

    test('WEAK_PASSWORD surfaces server message', () {
      expect(
        passwordResetMessageForRpc(_failure('WEAK_PASSWORD', message: 'Password must be at least 8 characters')),
        'Password must be at least 8 characters',
      );
    });

    test('RPC_NOT_APPLIED surfaces server message', () {
      expect(
        passwordResetMessageForRpc(_failure('RPC_NOT_APPLIED', message: 'Password reset was not applied.')),
        'Password reset was not applied.',
      );
    });

    test('unknown code falls back to generic message', () {
      expect(
        passwordResetMessageForRpc(_failure('UNKNOWN_CODE')),
        'Unable to reset the password. Check connectivity and try again.',
      );
    });
  });

  group('usernameUpdateMessageForRpc', () {
    test('FORBIDDEN', () {
      expect(
        usernameUpdateMessageForRpc(_failure('FORBIDDEN')),
        'You do not have permission to change staff usernames.',
      );
    });

    test('STAFF_NOT_FOUND', () {
      expect(
        usernameUpdateMessageForRpc(_failure('STAFF_NOT_FOUND')),
        'That staff member was not found. Refresh the list and try again.',
      );
    });

    test('CROSS_ORG_DENIED', () {
      expect(
        usernameUpdateMessageForRpc(_failure('CROSS_ORG_DENIED')),
        'That staff member is outside your clinic organization.',
      );
    });

    test('USERNAME_EXISTS', () {
      expect(
        usernameUpdateMessageForRpc(_failure('USERNAME_EXISTS')),
        'A staff account with this username already exists.',
      );
    });

    test('INVALID_INPUT surfaces server message', () {
      expect(
        usernameUpdateMessageForRpc(_failure('INVALID_INPUT', message: 'Username is required.')),
        'Username is required.',
      );
    });

    test('RPC_NOT_APPLIED surfaces server message', () {
      expect(
        usernameUpdateMessageForRpc(_failure('RPC_NOT_APPLIED', message: 'Username update was not applied.')),
        'Username update was not applied.',
      );
    });

    test('unknown code falls back to generic message', () {
      expect(
        usernameUpdateMessageForRpc(_failure('UNKNOWN_CODE')),
        'Unable to update the username. Check connectivity and try again.',
      );
    });
  });
}
