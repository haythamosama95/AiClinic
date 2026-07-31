import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:ai_clinic/features/billing/data/insurance_provider_repository.dart';
import 'package:ai_clinic/features/billing/presentation/providers/insurance_providers_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/auth_test_support.dart';
import '../../helpers/role_permission_seed.dart';
import '../../support/billing_rpc_test_client.dart';

void main() {
  group('InsuranceProvidersNotifier', () {
    test('build returns empty list without insurance access and issues no RPC', () async {
      final client = BillingRpcTestClient();
      final container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(
            () => _PresetAuthSessionNotifier(
              AuthSessionState(
                status: AuthSessionStatus.authenticated,
                context: sampleAuthSessionContext(
                  role: StaffRole.receptionist,
                  permissions: RolePermissionSeed.receptionist,
                ),
              ),
            ),
          ),
          insuranceProviderRepositoryProvider.overrideWithValue(InsuranceProviderRepository(client)),
        ],
      );
      addTearDown(container.dispose);

      final providers = await container.read(insuranceProvidersProvider.future);

      expect(providers, isEmpty);
      expect(client.rpcLog, isEmpty);
    });

    test('build lists all providers for authorized users', () async {
      final client = BillingRpcTestClient()
        ..insuranceProviders.add({
          'id': 'inactive-prov',
          'name': 'Inactive Plan',
          'contact_info': null,
          'is_active': false,
        });
      final container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(
            () => _PresetAuthSessionNotifier(
              AuthSessionState(
                status: AuthSessionStatus.authenticated,
                context: sampleAuthSessionContext(permissions: {PermissionKeys.insuranceManage}),
              ),
            ),
          ),
          insuranceProviderRepositoryProvider.overrideWithValue(InsuranceProviderRepository(client)),
        ],
      );
      addTearDown(container.dispose);

      final providers = await container.read(insuranceProvidersProvider.future);

      expect(client.lastFunction, 'list_insurance_providers');
      expect(client.lastParams?['p_only_active'], isFalse);
      expect(providers, hasLength(2));
      expect(providers.any((provider) => provider.id == 'inactive-prov'), isTrue);
    });

    test('reload refreshes providers on success', () async {
      final client = BillingRpcTestClient();
      final container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(
            () => _PresetAuthSessionNotifier(
              AuthSessionState(
                status: AuthSessionStatus.authenticated,
                context: sampleAuthSessionContext(permissions: {PermissionKeys.insuranceManage}),
              ),
            ),
          ),
          insuranceProviderRepositoryProvider.overrideWithValue(InsuranceProviderRepository(client)),
        ],
      );
      addTearDown(container.dispose);

      await container.read(insuranceProvidersProvider.future);
      client.insuranceProviders.add({
        'id': 'prov-reload',
        'name': 'Reloaded Provider',
        'contact_info': null,
        'is_active': true,
      });
      client.rpcLog.clear();

      await container.read(insuranceProvidersProvider.notifier).reload();

      expect(client.rpcLog, ['list_insurance_providers']);
      expect(
        container.read(insuranceProvidersProvider).value?.any((provider) => provider.id == 'prov-reload'),
        isTrue,
      );
    });

    test('reload surfaces repository errors', () async {
      final client = BillingRpcTestClient();
      final container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(
            () => _PresetAuthSessionNotifier(
              AuthSessionState(
                status: AuthSessionStatus.authenticated,
                context: sampleAuthSessionContext(permissions: {PermissionKeys.insuranceManage}),
              ),
            ),
          ),
          insuranceProviderRepositoryProvider.overrideWithValue(InsuranceProviderRepository(client)),
        ],
      );
      addTearDown(container.dispose);

      await container.read(insuranceProvidersProvider.future);
      client.rpcResults['list_insurance_providers'] = {
        'success': false,
        'error_code': 'RPC_ERROR',
        'error_message': 'Reload failed.',
      };

      await container.read(insuranceProvidersProvider.notifier).reload();

      final state = container.read(insuranceProvidersProvider);
      expect(state.hasError, isTrue);
      expect(state.error, isA<RpcFailure>());
    });

    test('upsert create returns provider id and reloads the list', () async {
      final client = BillingRpcTestClient();
      final container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(
            () => _PresetAuthSessionNotifier(
              AuthSessionState(
                status: AuthSessionStatus.authenticated,
                context: sampleAuthSessionContext(permissions: {PermissionKeys.insuranceManage}),
              ),
            ),
          ),
          insuranceProviderRepositoryProvider.overrideWithValue(InsuranceProviderRepository(client)),
        ],
      );
      addTearDown(container.dispose);

      await container.read(insuranceProvidersProvider.future);
      final initialCount = container.read(insuranceProvidersProvider).value?.length ?? 0;

      final providerId = await container.read(insuranceProvidersProvider.notifier).upsert(
        name: 'New Provider',
        contactInfo: 'claims@new.test',
      );

      expect(providerId, 'prov-2');
      expect(client.lastParams?['p_id'], isNull);
      expect(container.read(insuranceProvidersProvider).value, hasLength(initialCount + 1));
      expect(
        container.read(insuranceProvidersProvider).value?.any((provider) => provider.name == 'New Provider'),
        isTrue,
      );
    });

    test('upsert update returns provider id and reloads the list', () async {
      final client = BillingRpcTestClient();
      final container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(
            () => _PresetAuthSessionNotifier(
              AuthSessionState(
                status: AuthSessionStatus.authenticated,
                context: sampleAuthSessionContext(permissions: {PermissionKeys.insuranceManage}),
              ),
            ),
          ),
          insuranceProviderRepositoryProvider.overrideWithValue(InsuranceProviderRepository(client)),
        ],
      );
      addTearDown(container.dispose);

      await container.read(insuranceProvidersProvider.future);
      final existingId = BillingRpcTestClient.insuranceProviderId;

      final providerId = await container.read(insuranceProvidersProvider.notifier).upsert(
        id: existingId,
        name: 'Renamed Insurance',
        contactInfo: 'updated@acme.test',
      );

      expect(providerId, existingId);
      expect(client.lastParams?['p_id'], existingId);
      expect(
        container.read(insuranceProvidersProvider).value?.singleWhere((provider) => provider.id == existingId).name,
        'Renamed Insurance',
      );
    });

    test('upsert propagates validation failure and leaves list unchanged', () async {
      final client = BillingRpcTestClient();
      final container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(
            () => _PresetAuthSessionNotifier(
              AuthSessionState(
                status: AuthSessionStatus.authenticated,
                context: sampleAuthSessionContext(permissions: {PermissionKeys.insuranceManage}),
              ),
            ),
          ),
          insuranceProviderRepositoryProvider.overrideWithValue(InsuranceProviderRepository(client)),
        ],
      );
      addTearDown(container.dispose);

      await container.read(insuranceProvidersProvider.future);
      final before = container.read(insuranceProvidersProvider).value;
      client.rpcLog.clear();

      await expectLater(
        container.read(insuranceProvidersProvider.notifier).upsert(name: '   '),
        throwsA(isA<RpcFailure>().having((error) => error.code, 'code', 'INVALID_INPUT')),
      );

      expect(client.rpcLog, isEmpty);
      expect(container.read(insuranceProvidersProvider).value, before);
    });

    test('deactivate reloads the list on success', () async {
      final client = BillingRpcTestClient();
      final container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(
            () => _PresetAuthSessionNotifier(
              AuthSessionState(
                status: AuthSessionStatus.authenticated,
                context: sampleAuthSessionContext(permissions: {PermissionKeys.insuranceManage}),
              ),
            ),
          ),
          insuranceProviderRepositoryProvider.overrideWithValue(InsuranceProviderRepository(client)),
        ],
      );
      addTearDown(container.dispose);

      await container.read(insuranceProvidersProvider.future);
      final providerId = BillingRpcTestClient.insuranceProviderId;

      await container.read(insuranceProvidersProvider.notifier).deactivate(providerId);

      expect(client.lastFunction, 'list_insurance_providers');
      final provider = container.read(insuranceProvidersProvider).value?.singleWhere((row) => row.id == providerId);
      expect(provider?.isActive, isFalse);
    });

    test('deactivate propagates repository failures without changing the list', () async {
      final client = BillingRpcTestClient(
        rpcResults: {
          'insurance_provider_deactivate': {
            'success': false,
            'error_code': 'NOT_FOUND',
            'error_message': 'Provider not found.',
          },
        },
      );
      final container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(
            () => _PresetAuthSessionNotifier(
              AuthSessionState(
                status: AuthSessionStatus.authenticated,
                context: sampleAuthSessionContext(permissions: {PermissionKeys.insuranceManage}),
              ),
            ),
          ),
          insuranceProviderRepositoryProvider.overrideWithValue(InsuranceProviderRepository(client)),
        ],
      );
      addTearDown(container.dispose);

      await container.read(insuranceProvidersProvider.future);
      final before = container.read(insuranceProvidersProvider).value;

      await expectLater(
        container.read(insuranceProvidersProvider.notifier).deactivate('missing-provider'),
        throwsA(isA<RpcFailure>().having((error) => error.code, 'code', 'NOT_FOUND')),
      );

      expect(container.read(insuranceProvidersProvider).value, before);
    });
  });

  group('activeInsuranceProvidersProvider', () {
    test('requests only active providers independently of notifier state', () async {
      final client = BillingRpcTestClient()
        ..insuranceProviders.add({
          'id': 'inactive-prov',
          'name': 'Inactive Plan',
          'contact_info': null,
          'is_active': false,
        });
      final container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(
            () => _PresetAuthSessionNotifier(
              AuthSessionState(
                status: AuthSessionStatus.authenticated,
                context: sampleAuthSessionContext(permissions: {PermissionKeys.insuranceManage}),
              ),
            ),
          ),
          insuranceProviderRepositoryProvider.overrideWithValue(InsuranceProviderRepository(client)),
        ],
      );
      addTearDown(container.dispose);

      final allProviders = await container.read(insuranceProvidersProvider.future);
      expect(allProviders, hasLength(2));

      client.rpcLog.clear();
      final activeProviders = await container.read(activeInsuranceProvidersProvider.future);

      expect(client.lastFunction, 'list_insurance_providers');
      expect(client.lastParams?['p_only_active'], isTrue);
      expect(activeProviders, hasLength(1));
      expect(activeProviders.single.id, BillingRpcTestClient.insuranceProviderId);
      expect(container.read(insuranceProvidersProvider).value, allProviders);
    });
  });
}

class _PresetAuthSessionNotifier extends TestAuthSessionNotifier {
  _PresetAuthSessionNotifier(this.initial);

  final AuthSessionState initial;

  @override
  AuthSessionState build() => initial;
}
