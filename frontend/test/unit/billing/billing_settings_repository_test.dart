import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/billing/data/billing_settings_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/billing_rpc_test_client.dart';

void main() {
  test('get throws RpcFailure when response shape is unexpected', () async {
    final client = BillingRpcTestClient(
      rpcResults: {
        'get_billing_settings': {'success': true, 'data': {}},
      },
    );
    final repo = BillingSettingsRepository(client);

    expect(() => repo.get(), throwsA(isA<RpcFailure>().having((error) => error.code, 'code', 'UNEXPECTED_RESPONSE')));
  });
}
