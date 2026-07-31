import 'dart:async';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:ai_clinic/features/billing/data/billing_settings_repository.dart';
import 'package:ai_clinic/features/billing/domain/billing_settings.dart';
import 'package:ai_clinic/features/billing/presentation/providers/billing_settings_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../helpers/auth_test_support.dart';
import '../../helpers/role_permission_seed.dart';
import '../../support/billing_rpc_test_client.dart';

void main() {
  group('BillingSettingsNotifier', () {
    test('build returns defaults without billing access and issues no RPC', () async {
      final client = BillingRpcTestClient();
      final container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(
            () => _PresetAuthSessionNotifier(
              AuthSessionState(
                status: AuthSessionStatus.authenticated,
                context: sampleAuthSessionContext(
                  role: StaffRole.doctor,
                  permissions: RolePermissionSeed.doctor,
                ),
              ),
            ),
          ),
          billingSettingsRepositoryProvider.overrideWithValue(BillingSettingsRepository(client)),
        ],
      );
      addTearDown(container.dispose);

      final settings = await container.read(billingSettingsProvider.future);

      expect(settings.allowPartialPayments, isFalse);
      expect(client.rpcLog, isEmpty);
    });

    test('build fetches settings for authorized users', () async {
      final client = BillingRpcTestClient()..allowPartialPayments = true;
      final container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(
            () => _PresetAuthSessionNotifier(
              AuthSessionState(
                status: AuthSessionStatus.authenticated,
                context: sampleAuthSessionContext(
                  role: StaffRole.receptionist,
                  permissions: {PermissionKeys.invoicesView},
                ),
              ),
            ),
          ),
          billingSettingsRepositoryProvider.overrideWithValue(BillingSettingsRepository(client)),
        ],
      );
      addTearDown(container.dispose);

      final settings = await container.read(billingSettingsProvider.future);

      expect(client.rpcLog, ['get_billing_settings']);
      expect(settings.allowPartialPayments, isTrue);
    });

    test('build surfaces repository errors', () async {
      final client = BillingRpcTestClient(
        rpcResults: {
          'get_billing_settings': {
            'success': false,
            'error_code': 'RPC_ERROR',
            'error_message': 'Settings unavailable.',
          },
        },
      );
      final container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(
            () => _PresetAuthSessionNotifier(
              AuthSessionState(
                status: AuthSessionStatus.authenticated,
                context: sampleAuthSessionContext(
                  permissions: {PermissionKeys.paymentsRecord},
                ),
              ),
            ),
          ),
          billingSettingsRepositoryProvider.overrideWithValue(BillingSettingsRepository(client)),
        ],
      );
      addTearDown(container.dispose);

      final subscription = container.listen(billingSettingsProvider, (_, _) {});
      addTearDown(subscription.close);

      container.read(billingSettingsProvider);
      await pumpEventQueue();

      final state = container.read(billingSettingsProvider);
      expect(state.hasError, isTrue);
      expect(
        state.error,
        isA<RpcFailure>().having((error) => error.code, 'code', 'RPC_ERROR'),
      );
    });

    test('reload refreshes settings on success', () async {
      final client = BillingRpcTestClient();
      final container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(
            () => _PresetAuthSessionNotifier(
              AuthSessionState(
                status: AuthSessionStatus.authenticated,
                context: sampleAuthSessionContext(permissions: {PermissionKeys.invoicesView}),
              ),
            ),
          ),
          billingSettingsRepositoryProvider.overrideWithValue(BillingSettingsRepository(client)),
        ],
      );
      addTearDown(container.dispose);

      await container.read(billingSettingsProvider.future);
      client.allowPartialPayments = true;
      client.rpcLog.clear();

      await container.read(billingSettingsProvider.notifier).reload();

      expect(client.rpcLog, ['get_billing_settings']);
      expect(container.read(billingSettingsProvider).value?.allowPartialPayments, isTrue);
    });

    test('reload surfaces repository errors', () async {
      final client = BillingRpcTestClient();
      final container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(
            () => _PresetAuthSessionNotifier(
              AuthSessionState(
                status: AuthSessionStatus.authenticated,
                context: sampleAuthSessionContext(permissions: {PermissionKeys.invoicesView}),
              ),
            ),
          ),
          billingSettingsRepositoryProvider.overrideWithValue(BillingSettingsRepository(client)),
        ],
      );
      addTearDown(container.dispose);

      await container.read(billingSettingsProvider.future);
      client.rpcResults['get_billing_settings'] = {
        'success': false,
        'error_code': 'RPC_ERROR',
        'error_message': 'Reload failed.',
      };

      await container.read(billingSettingsProvider.notifier).reload();

      final state = container.read(billingSettingsProvider);
      expect(state.hasError, isTrue);
      expect(state.error, isA<RpcFailure>());
    });

    test('updateAllowPartialPayments sends RPC, refreshes state, and shows loading', () async {
      final client = _DelayedUpdateBillingRpcClient(updateDelay: const Duration(milliseconds: 50));
      final container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(
            () => _PresetAuthSessionNotifier(
              AuthSessionState(
                status: AuthSessionStatus.authenticated,
                context: sampleAuthSessionContext(permissions: {PermissionKeys.invoicesView}),
              ),
            ),
          ),
          billingSettingsRepositoryProvider.overrideWithValue(BillingSettingsRepository(client)),
        ],
      );
      addTearDown(container.dispose);

      await container.read(billingSettingsProvider.future);
      expect(container.read(billingSettingsProvider).value?.allowPartialPayments, isFalse);

      final updateFuture = container.read(billingSettingsProvider.notifier).updateAllowPartialPayments(true);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(billingSettingsProvider), isA<AsyncLoading<BillingSettings>>());

      await updateFuture;

      expect(client.rpcLog, contains('update_billing_settings'));
      expect(
        client.rpcLog.lastIndexWhere((fn) => fn == 'update_billing_settings'),
        lessThan(client.rpcLog.lastIndexWhere((fn) => fn == 'get_billing_settings')),
      );
      expect(client.allowPartialPayments, isTrue);
      expect(client.rpcLog.where((fn) => fn == 'get_billing_settings').length, greaterThanOrEqualTo(2));
      expect(container.read(billingSettingsProvider).value?.allowPartialPayments, isTrue);
    });

    test('updateAllowPartialPayments rolls back to previous value on failure', () async {
      final client = BillingRpcTestClient();
      final container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(
            () => _PresetAuthSessionNotifier(
              AuthSessionState(
                status: AuthSessionStatus.authenticated,
                context: sampleAuthSessionContext(permissions: {PermissionKeys.invoicesView}),
              ),
            ),
          ),
          billingSettingsRepositoryProvider.overrideWithValue(BillingSettingsRepository(client)),
        ],
      );
      addTearDown(container.dispose);

      await container.read(billingSettingsProvider.future);
      client.rpcResults['update_billing_settings'] = {
        'success': false,
        'error_code': 'RPC_ERROR',
        'error_message': 'Update rejected.',
      };

      await container.read(billingSettingsProvider.notifier).updateAllowPartialPayments(true);

      final state = container.read(billingSettingsProvider);
      expect(state.hasError, isFalse);
      expect(state.value?.allowPartialPayments, isFalse);
    });

    test('updateAllowPartialPayments leaves AsyncError when there was no previous value', () async {
      final client = BillingRpcTestClient(
        rpcResults: {
          'get_billing_settings': {
            'success': false,
            'error_code': 'RPC_ERROR',
            'error_message': 'Initial load failed.',
          },
        },
      );
      final container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(
            () => _PresetAuthSessionNotifier(
              AuthSessionState(
                status: AuthSessionStatus.authenticated,
                context: sampleAuthSessionContext(permissions: {PermissionKeys.invoicesView}),
              ),
            ),
          ),
          billingSettingsRepositoryProvider.overrideWithValue(BillingSettingsRepository(client)),
        ],
      );
      addTearDown(container.dispose);

      final subscription = container.listen(billingSettingsProvider, (_, _) {});
      addTearDown(subscription.close);

      container.read(billingSettingsProvider);
      await pumpEventQueue();
      expect(container.read(billingSettingsProvider).hasError, isTrue);

      client.rpcResults.remove('get_billing_settings');
      client.rpcResults['update_billing_settings'] = {
        'success': false,
        'error_code': 'RPC_ERROR',
        'error_message': 'Update rejected.',
      };

      await container.read(billingSettingsProvider.notifier).updateAllowPartialPayments(true);

      final state = container.read(billingSettingsProvider);
      expect(state.hasError, isTrue);
      expect(state.error, isA<RpcFailure>());
    });
  });
}

class _PresetAuthSessionNotifier extends TestAuthSessionNotifier {
  _PresetAuthSessionNotifier(this.initial);

  final AuthSessionState initial;

  @override
  AuthSessionState build() => initial;
}

class _DelayedUpdateBillingRpcClient extends BillingRpcTestClient {
  _DelayedUpdateBillingRpcClient({required this.updateDelay});

  final Duration updateDelay;

  @override
  PostgrestFilterBuilder<T> rpc<T>(String fn, {Map<String, dynamic>? params, dynamic get = false}) {
    if (fn == 'update_billing_settings') {
      rpcLog.add(fn);
      lastFunction = fn;
      lastParams = params == null ? null : Map<String, dynamic>.from(params);
      allowPartialPayments = lastParams?['p_allow_partial_payments'] == true;
      return _DelayedFakePostgrestRpc(
        {
          'success': true,
          'data': {'allow_partial_payments': allowPartialPayments},
        },
        updateDelay,
      ) as PostgrestFilterBuilder<T>;
    }
    return super.rpc<T>(fn, params: params, get: get);
  }
}

class _DelayedFakePostgrestRpc extends Fake implements PostgrestFilterBuilder<dynamic> {
  _DelayedFakePostgrestRpc(this.result, this.delay);

  final dynamic result;
  final Duration delay;

  @override
  Future<R> then<R>(FutureOr<R> Function(dynamic value) onValue, {Function? onError}) {
    return Future<dynamic>.delayed(delay, () => result).then(onValue, onError: onError);
  }
}
