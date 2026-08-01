import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/billing/data/insurance_provider_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/billing_rpc_test_client.dart';

void main() {
  late BillingRpcTestClient client;
  late InsuranceProviderRepository repo;

  setUp(() {
    client = BillingRpcTestClient();
    repo = InsuranceProviderRepository(client);
  });

  test('upsertProvider rejects whitespace-only names before RPC', () {
    expect(
      () => repo.upsertProvider(name: '   '),
      throwsA(isA<RpcFailure>().having((error) => error.code, 'code', 'INVALID_INPUT')),
    );
  });

  test('upsertProvider sends explicit null p_id on create', () async {
    final providerId = await repo.upsertProvider(
      name: 'Dev Seed Insurance Co.',
      contactInfo: 'claims@dev-seed.example.com',
    );

    expect(client.lastFunction, 'insurance_provider_upsert');
    expect(client.lastParams?['p_id'], isNull);
    expect(client.lastParams?['p_name'], 'Dev Seed Insurance Co.');
    expect(providerId, isNotEmpty);
  });

  test('listProviders returns active providers by default', () async {
    final providers = await repo.listProviders();

    expect(client.lastFunction, 'list_insurance_providers');
    expect(client.lastParams?['p_only_active'], isTrue);
    expect(providers, hasLength(1));
    expect(providers.first.id, BillingRpcTestClient.insuranceProviderId);
    expect(providers.first.name, 'Acme Insurance');
  });

  test('listProviders forwards onlyActive false', () async {
    await repo.listProviders(onlyActive: false);

    expect(client.lastParams?['p_only_active'], isFalse);
  });

  test('listProviders returns empty list when providers are absent', () async {
    client = BillingRpcTestClient(
      rpcResults: {
        'list_insurance_providers': {'success': true, 'data': {}},
      },
    );
    repo = InsuranceProviderRepository(client);

    final providers = await repo.listProviders();

    expect(providers, isEmpty);
  });

  test('listProviders parses items key when providers is absent', () async {
    client = BillingRpcTestClient(
      rpcResults: {
        'list_insurance_providers': {
          'success': true,
          'data': {
            'items': [
              {
                'id': BillingRpcTestClient.insuranceProviderId,
                'name': 'Acme Insurance',
                'contact_info': 'claims@acme.test',
                'is_active': true,
              },
              {'id': '', 'name': 'Invalid'},
            ],
          },
        },
      },
    );
    repo = InsuranceProviderRepository(client);

    final providers = await repo.listProviders();

    expect(providers, hasLength(1));
    expect(providers.first.id, BillingRpcTestClient.insuranceProviderId);
  });

  test('upsertProvider updates existing provider when id is provided', () async {
    final providerId = await repo.upsertProvider(
      id: BillingRpcTestClient.insuranceProviderId,
      name: '  Updated Insurance  ',
      contactInfo: '  billing@updated.test  ',
    );

    expect(client.lastFunction, 'insurance_provider_upsert');
    expect(client.lastParams?['p_id'], BillingRpcTestClient.insuranceProviderId);
    expect(client.lastParams?['p_name'], 'Updated Insurance');
    expect(client.lastParams?['p_contact_info'], '  billing@updated.test  ');
    expect(providerId, BillingRpcTestClient.insuranceProviderId);
  });

  test('upsertProvider coerces whitespace-only id to null', () async {
    await repo.upsertProvider(id: '   ', name: 'New Provider');

    expect(client.lastParams?['p_id'], isNull);
  });

  test('upsertProvider throws StateError when provider id is missing', () async {
    client = BillingRpcTestClient(
      rpcResults: {
        'insurance_provider_upsert': {'success': true, 'data': null},
      },
    );
    repo = InsuranceProviderRepository(client);

    expect(
      () => repo.upsertProvider(name: 'New Provider'),
      throwsA(isA<StateError>()),
    );
  });

  test('deactivateProvider succeeds and forwards trimmed id', () async {
    await repo.deactivateProvider(providerId: '  ${BillingRpcTestClient.insuranceProviderId}  ');

    expect(client.lastFunction, 'insurance_provider_deactivate');
    expect(client.lastParams?['p_id'], BillingRpcTestClient.insuranceProviderId);
    expect(
      client.insuranceProviders.firstWhere((row) => row['id'] == BillingRpcTestClient.insuranceProviderId)['is_active'],
      isFalse,
    );
  });

  test('deactivateProvider rejects empty providerId before RPC', () {
    expect(
      () => repo.deactivateProvider(providerId: '   '),
      throwsA(isA<RpcFailure>().having((error) => error.code, 'code', 'INVALID_INPUT')),
    );
    expect(client.rpcLog, isEmpty);
  });
}
