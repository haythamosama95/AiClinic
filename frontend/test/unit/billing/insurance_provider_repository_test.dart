import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/billing/data/insurance_provider_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/billing_rpc_test_client.dart';

void main() {
  test('upsertProvider rejects whitespace-only names before RPC', () {
    final repo = InsuranceProviderRepository(BillingRpcTestClient());

    expect(
      () => repo.upsertProvider(name: '   '),
      throwsA(isA<RpcFailure>().having((error) => error.code, 'code', 'INVALID_INPUT')),
    );
  });
}
