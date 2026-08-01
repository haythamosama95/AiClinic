import 'dart:async';

import 'package:ai_clinic/features/service_catalog/data/service_catalog_repository.dart';
import 'package:ai_clinic/features/service_catalog/domain/effective_price.dart';
import 'package:ai_clinic/features/service_catalog/presentation/providers/service_selector_notifier.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../support/fake_postgrest_rpc.dart';

const _branchId = 'branch-1';

void main() {
  group('ServiceSelectorNotifier', () {
    test('build returns empty list initially', () async {
      final container = ProviderContainer(
        overrides: [
          serviceCatalogRepositoryProvider.overrideWithValue(ServiceCatalogRepository(_SearchEligibleRpcClient())),
        ],
      );
      addTearDown(container.dispose);

      final results = await container.read(serviceSelectorProvider(_branchId).future);
      expect(results, isEmpty);
    });

    test('search debounces and loads results from repository', () {
      FakeAsync().run((async) {
        final rpcClient = _SearchEligibleRpcClient();
        final container = ProviderContainer(
          overrides: [
            serviceCatalogRepositoryProvider.overrideWithValue(ServiceCatalogRepository(rpcClient)),
          ],
        );
        addTearDown(container.dispose);

        container.listen(serviceSelectorProvider(_branchId), (_, _) {});
        async.flushMicrotasks();

        final notifier = container.read(serviceSelectorProvider(_branchId).notifier);
        notifier.search('consult', debounce: const Duration(milliseconds: 300));

        expect(rpcClient.lastFunction, isNull);

        async.elapse(const Duration(milliseconds: 300));
        async.flushMicrotasks();

        expect(rpcClient.lastFunction, 'search_eligible_services');
        expect(rpcClient.lastParams?['p_branch_id'], _branchId);
        expect(rpcClient.lastParams?['p_query'], 'consult');

        final state = container.read(serviceSelectorProvider(_branchId));
        expect(state.value, hasLength(1));
        expect(state.value?.first.name, 'Service consult');
        expect(state.value?.first.appliedRule, AppliedPriceRule.defaultPrice);
      });
    });

    test('search with empty query loads eligible services', () {
      FakeAsync().run((async) {
        final rpcClient = _SearchEligibleRpcClient();
        final container = ProviderContainer(
          overrides: [
            serviceCatalogRepositoryProvider.overrideWithValue(ServiceCatalogRepository(rpcClient)),
          ],
        );
        addTearDown(container.dispose);

        container.listen(serviceSelectorProvider(_branchId), (_, _) {});
        async.flushMicrotasks();

        container.read(serviceSelectorProvider(_branchId).notifier).search('', debounce: const Duration(milliseconds: 50));
        async.elapse(const Duration(milliseconds: 50));
        async.flushMicrotasks();

        expect(rpcClient.lastParams?['p_query'], '');
        final state = container.read(serviceSelectorProvider(_branchId));
        expect(state.value, hasLength(1));
        expect(state.value?.first.serviceId, 'svc-');
      });
    });

    test('RPC error sets AsyncError state', () {
      FakeAsync().run((async) {
        final rpcClient = _SearchEligibleRpcClient(shouldFail: true);
        final container = ProviderContainer(
          overrides: [
            serviceCatalogRepositoryProvider.overrideWithValue(ServiceCatalogRepository(rpcClient)),
          ],
        );
        addTearDown(container.dispose);

        container.listen(serviceSelectorProvider(_branchId), (_, _) {});
        async.flushMicrotasks();

        container.read(serviceSelectorProvider(_branchId).notifier).search('fail', debounce: const Duration(milliseconds: 50));
        async.elapse(const Duration(milliseconds: 50));
        async.flushMicrotasks();

        final state = container.read(serviceSelectorProvider(_branchId));
        expect(state.hasError, isTrue);
        expect(state.error, isA<Exception>());
      });
    });

    test('rapid consecutive searches discard stale results', () {
      FakeAsync().run((async) {
        final rpcClient = _DelayedSearchEligibleRpcClient();
        final container = ProviderContainer(
          overrides: [
            serviceCatalogRepositoryProvider.overrideWithValue(ServiceCatalogRepository(rpcClient)),
          ],
        );
        addTearDown(container.dispose);

        container.listen(serviceSelectorProvider(_branchId), (_, _) {});
        async.flushMicrotasks();

        final notifier = container.read(serviceSelectorProvider(_branchId).notifier);
        notifier.search('slow', debounce: const Duration(milliseconds: 50));
        async.elapse(const Duration(milliseconds: 50));
        async.flushMicrotasks();

        notifier.search('fast', debounce: const Duration(milliseconds: 50));
        async.elapse(const Duration(milliseconds: 50));
        async.flushMicrotasks();

        final midState = container.read(serviceSelectorProvider(_branchId));
        expect(midState.value?.first.serviceId, 'svc-fast');

        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();

        final finalState = container.read(serviceSelectorProvider(_branchId));
        expect(finalState.value?.first.serviceId, 'svc-fast');
        expect(finalState.value?.first.name, 'Service fast');
      });
    });
  });
}

class _SearchEligibleRpcClient extends RpcCaptureSupabaseClient {
  _SearchEligibleRpcClient({this.shouldFail = false});

  final bool shouldFail;

  @override
  PostgrestFilterBuilder<T> rpc<T>(String fn, {Map<String, dynamic>? params, dynamic get = false}) {
    lastFunction = fn;
    lastParams = params == null ? null : Map<String, dynamic>.from(params);
    if (fn == 'search_eligible_services' && shouldFail) {
      return FakePostgrestRpc({
        'success': false,
        'error_code': 'RPC_ERROR',
        'error_message': 'Search failed.',
      }) as PostgrestFilterBuilder<T>;
    }
    return FakePostgrestRpc(_payloadFor(fn, params)) as PostgrestFilterBuilder<T>;
  }

  Map<String, dynamic> _payloadFor(String fn, Map<String, dynamic>? params) {
    if (fn == 'search_eligible_services') {
      final query = params?['p_query']?.toString() ?? '';
      return {
        'success': true,
        'data': {
          'items': [
            {
              'service_id': 'svc-$query',
              'name': 'Service $query',
              'unit_price': '100.00',
              'applied_rule': 'default',
              'on_promotion': false,
            },
          ],
        },
      };
    }
    return {'success': true, 'data': <String, dynamic>{}};
  }
}

class _DelayedSearchEligibleRpcClient extends _SearchEligibleRpcClient {
  @override
  PostgrestFilterBuilder<T> rpc<T>(String fn, {Map<String, dynamic>? params, dynamic get = false}) {
    if (fn == 'search_eligible_services') {
      final query = params?['p_query']?.toString() ?? '';
      if (query == 'slow') {
        return _DelayedPostgrestRpc(
          Future<void>.delayed(const Duration(milliseconds: 500)),
          _payloadFor(fn, params),
        ) as PostgrestFilterBuilder<T>;
      }
    }
    return super.rpc<T>(fn, params: params, get: get);
  }
}

class _DelayedPostgrestRpc extends FakePostgrestRpc {
  _DelayedPostgrestRpc(this._delay, super.result);

  final Future<void> _delay;

  @override
  Future<R> then<R>(FutureOr<R> Function(dynamic value) onValue, {Function? onError}) {
    return _delay.then((_) => Future<dynamic>.value(result).then(onValue, onError: onError));
  }
}
