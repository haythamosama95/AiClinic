import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/billing/data/billing_settings_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/billing_rpc_test_client.dart';

void main() {
  late BillingRpcTestClient client;
  late BillingSettingsRepository repo;

  setUp(() {
    client = BillingRpcTestClient();
    repo = BillingSettingsRepository(client);
  });

  test('get throws RpcFailure when response shape is unexpected', () async {
    client = BillingRpcTestClient(
      rpcResults: {
        'get_billing_settings': {'success': true, 'data': {}},
      },
    );
    repo = BillingSettingsRepository(client);

    expect(() => repo.get(), throwsA(isA<RpcFailure>().having((error) => error.code, 'code', 'UNEXPECTED_RESPONSE')));
  });

  test('get returns parsed billing settings', () async {
    client.allowPartialPayments = true;

    final settings = await repo.get();

    expect(client.lastFunction, 'get_billing_settings');
    expect(settings.allowPartialPayments, isTrue);
  });

  test('update sends p_allow_partial_payments true', () async {
    await repo.update(allowPartialPayments: true);

    expect(client.lastFunction, 'update_billing_settings');
    expect(client.lastParams?['p_allow_partial_payments'], isTrue);
    expect(client.allowPartialPayments, isTrue);
  });

  test('update sends p_allow_partial_payments false', () async {
    client.allowPartialPayments = true;

    await repo.update(allowPartialPayments: false);

    expect(client.lastFunction, 'update_billing_settings');
    expect(client.lastParams?['p_allow_partial_payments'], isFalse);
    expect(client.allowPartialPayments, isFalse);
  });

  test('update propagates server RPC failure', () async {
    client = BillingRpcTestClient(
      rpcResults: {
        'update_billing_settings': {
          'success': false,
          'error_code': 'RPC_ERROR',
          'error_message': 'Update rejected.',
        },
      },
    );
    repo = BillingSettingsRepository(client);

    expect(
      () => repo.update(allowPartialPayments: true),
      throwsA(isA<RpcFailure>().having((error) => error.code, 'code', 'RPC_ERROR')),
    );
  });
}
