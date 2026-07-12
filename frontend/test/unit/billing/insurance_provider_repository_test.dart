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

  test('upsertProvider sends explicit null p_id on create', () async {
    final client = BillingRpcTestClient();
    final repo = InsuranceProviderRepository(client);

    final providerId = await repo.upsertProvider(
      name: 'Dev Seed Insurance Co.',
      contactInfo: 'claims@dev-seed.example.com',
    );

    expect(client.lastFunction, 'insurance_provider_upsert');
    expect(client.lastParams?['p_id'], isNull);
    expect(client.lastParams?['p_name'], 'Dev Seed Insurance Co.');
    expect(providerId, isNotEmpty);
  });
}
