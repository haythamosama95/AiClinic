import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/setup/presentation/providers/provisioning_notifier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('provisioning RPC messages', () {
    test('WEAK_PASSWORD surfaces server message for create', () {
      final failure = RpcFailure(
        RpcResult(success: false, errorCode: 'WEAK_PASSWORD', errorMessage: 'Password must contain at least one digit'),
      );

      expect(provisioningMessageForRpc(failure), 'Password must contain at least one digit');
    });

    test('WEAK_PASSWORD surfaces server message for password reset', () {
      final failure = RpcFailure(
        RpcResult(success: false, errorCode: 'WEAK_PASSWORD', errorMessage: 'Password must be at least 8 characters'),
      );

      expect(passwordResetMessageForRpc(failure), 'Password must be at least 8 characters');
    });
  });
}
