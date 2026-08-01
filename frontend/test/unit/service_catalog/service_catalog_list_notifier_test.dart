import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/service_catalog/data/service_catalog_repository.dart';
import 'package:ai_clinic/features/service_catalog/domain/global_status.dart';
import 'package:ai_clinic/features/service_catalog/presentation/models/service_list_filters.dart';
import 'package:ai_clinic/features/service_catalog/presentation/providers/service_catalog_list_notifier.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../helpers/auth_test_support.dart';
import '../../support/fake_postgrest_rpc.dart';

void main() {
  group('ServiceCatalogListNotifier', () {
    test('loads filtered services for authorized users', () async {
      final rpcClient = _ListServicesRpcClient();
      final container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(
            () => _PresetAuthSessionNotifier(
              AuthSessionState(
                status: AuthSessionStatus.authenticated,
                context: sampleAuthSessionContext(role: StaffRole.administrator, permissions: {'services.view'}),
              ),
            ),
          ),
          serviceCatalogRepositoryProvider.overrideWithValue(ServiceCatalogRepository(rpcClient)),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(serviceCatalogListProvider.notifier)
          .applyFilters(const ServiceListFilters(query: 'consult', globalStatus: GlobalStatus.active));

      expect(rpcClient.lastParams?['p_query'], 'consult');
      expect(rpcClient.lastParams?['p_global_status'], 'active');

      final state = container.read(serviceCatalogListProvider);
      expect(state.value?.items, hasLength(1));
      expect(state.value?.total, 1);
      expect(state.value?.items.first.name, 'Consultation');
    });

    test('returns empty list when user lacks catalog permissions', () async {
      final container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(
            () => _PresetAuthSessionNotifier(
              AuthSessionState(
                status: AuthSessionStatus.authenticated,
                context: sampleAuthSessionContext(role: StaffRole.receptionist, permissions: const {}),
              ),
            ),
          ),
          serviceCatalogRepositoryProvider.overrideWithValue(ServiceCatalogRepository(_ListServicesRpcClient())),
        ],
      );
      addTearDown(container.dispose);

      final state = await container.read(serviceCatalogListProvider.future);
      expect(state.items, isEmpty);
      expect(state.total, 0);
    });

    test('reload re-fetches with current filters', () async {
      final rpcClient = _ConfigurableListServicesRpcClient();
      final container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(
            () => _PresetAuthSessionNotifier(
              AuthSessionState(
                status: AuthSessionStatus.authenticated,
                context: sampleAuthSessionContext(role: StaffRole.administrator, permissions: {'services.view'}),
              ),
            ),
          ),
          serviceCatalogRepositoryProvider.overrideWithValue(ServiceCatalogRepository(rpcClient)),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(serviceCatalogListProvider.notifier)
          .applyFilters(const ServiceListFilters(query: 'consult', globalStatus: GlobalStatus.active));

      rpcClient.itemName = 'Follow-up';
      await container.read(serviceCatalogListProvider.notifier).reload();

      expect(rpcClient.listCallCount, greaterThanOrEqualTo(2));
      expect(rpcClient.lastParams?['p_query'], 'consult');
      expect(rpcClient.lastParams?['p_global_status'], 'active');

      final state = container.read(serviceCatalogListProvider);
      expect(state.value?.items.first.name, 'Follow-up');
      expect(state.value?.filters.query, 'consult');
    });

    test('applyFilters updates state with hasMore and isEmpty', () async {
      final rpcClient = _ConfigurableListServicesRpcClient(total: 10, itemCount: 1);
      final container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(
            () => _PresetAuthSessionNotifier(
              AuthSessionState(
                status: AuthSessionStatus.authenticated,
                context: sampleAuthSessionContext(role: StaffRole.administrator, permissions: {'services.view'}),
              ),
            ),
          ),
          serviceCatalogRepositoryProvider.overrideWithValue(ServiceCatalogRepository(rpcClient)),
        ],
      );
      addTearDown(container.dispose);

      await container.read(serviceCatalogListProvider.notifier).applyFilters(const ServiceListFilters());

      final state = container.read(serviceCatalogListProvider).value!;
      expect(state.isEmpty, isFalse);
      expect(state.hasMore, isTrue);
      expect(state.total, 10);
      expect(state.items, hasLength(1));
    });

    test('applyFilters reports empty catalog', () async {
      final rpcClient = _ConfigurableListServicesRpcClient(total: 0, itemCount: 0);
      final container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(
            () => _PresetAuthSessionNotifier(
              AuthSessionState(
                status: AuthSessionStatus.authenticated,
                context: sampleAuthSessionContext(role: StaffRole.administrator, permissions: {'services.view'}),
              ),
            ),
          ),
          serviceCatalogRepositoryProvider.overrideWithValue(ServiceCatalogRepository(rpcClient)),
        ],
      );
      addTearDown(container.dispose);

      await container.read(serviceCatalogListProvider.notifier).applyFilters(const ServiceListFilters());

      final state = container.read(serviceCatalogListProvider).value!;
      expect(state.isEmpty, isTrue);
      expect(state.hasMore, isFalse);
      expect(state.total, 0);
    });

    test('RPC failure surfaces as AsyncError', () async {
      final rpcClient = _ConfigurableListServicesRpcClient();
      final container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(
            () => _PresetAuthSessionNotifier(
              AuthSessionState(
                status: AuthSessionStatus.authenticated,
                context: sampleAuthSessionContext(role: StaffRole.administrator, permissions: {'services.view'}),
              ),
            ),
          ),
          serviceCatalogRepositoryProvider.overrideWithValue(ServiceCatalogRepository(rpcClient)),
        ],
      );
      addTearDown(container.dispose);

      await container.read(serviceCatalogListProvider.future);

      rpcClient.shouldFail = true;
      await container.read(serviceCatalogListProvider.notifier).applyFilters(const ServiceListFilters(query: 'fail'));

      final state = container.read(serviceCatalogListProvider);
      expect(state.hasError, isTrue);
      expect(state.error, isA<Exception>());
    });

    test('reload returns empty for unauthorized user without calling RPC', () async {
      final rpcClient = _ConfigurableListServicesRpcClient();
      final container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(
            () => _PresetAuthSessionNotifier(
              AuthSessionState(
                status: AuthSessionStatus.authenticated,
                context: sampleAuthSessionContext(role: StaffRole.receptionist, permissions: const {}),
              ),
            ),
          ),
          serviceCatalogRepositoryProvider.overrideWithValue(ServiceCatalogRepository(rpcClient)),
        ],
      );
      addTearDown(container.dispose);

      final initial = await container.read(serviceCatalogListProvider.future);
      expect(initial.items, isEmpty);
      expect(rpcClient.listCallCount, 0);

      await container.read(serviceCatalogListProvider.notifier).reload();

      expect(rpcClient.listCallCount, 0);
      final state = container.read(serviceCatalogListProvider).value!;
      expect(state.items, isEmpty);
      expect(state.total, 0);
    });
  });
}

class _ConfigurableListServicesRpcClient extends RpcCaptureSupabaseClient {
  _ConfigurableListServicesRpcClient({
    this.shouldFail = false,
    this.total = 1,
    this.itemCount = 1,
    this.itemName = 'Consultation',
  });

  bool shouldFail;
  final int total;
  final int itemCount;
  String itemName;
  int listCallCount = 0;

  @override
  PostgrestFilterBuilder<T> rpc<T>(String fn, {Map<String, dynamic>? params, dynamic get = false}) {
    lastParams = params;
    if (fn == 'list_services') {
      listCallCount++;
      if (shouldFail) {
        return FakePostgrestRpc({
          'success': false,
          'error_code': 'RPC_ERROR',
          'error_message': 'List failed.',
        }) as PostgrestFilterBuilder<T>;
      }
      return FakePostgrestRpc(_listPayload()) as PostgrestFilterBuilder<T>;
    }
    return FakePostgrestRpc({'success': true, 'data': <String, dynamic>{}}) as PostgrestFilterBuilder<T>;
  }

  Map<String, dynamic> _listPayload() {
    final items = <Map<String, dynamic>>[];
    for (var i = 0; i < itemCount; i++) {
      items.add({
        'service_id': 'service-${i + 1}',
        'name': itemName,
        'default_price': '200.00',
        'global_status': 'active',
        'assigned_branch_count': 2,
        'updated_at': '2026-01-01T10:00:00.000Z',
      });
    }
    return {
      'success': true,
      'data': {'total': total, 'items': items},
    };
  }
}

class _ListServicesRpcClient extends RpcCaptureSupabaseClient {
  @override
  PostgrestFilterBuilder<T> rpc<T>(String fn, {Map<String, dynamic>? params, dynamic get = false}) {
    lastParams = params;
    return FakePostgrestRpc(_payloadFor(fn)) as PostgrestFilterBuilder<T>;
  }

  Map<String, dynamic> _payloadFor(String fn) {
    return switch (fn) {
      'list_services' => {
        'success': true,
        'data': {
          'total': 1,
          'items': [
            {
              'service_id': 'service-1',
              'name': 'Consultation',
              'default_price': '200.00',
              'global_status': 'active',
              'assigned_branch_count': 2,
              'updated_at': '2026-01-01T10:00:00.000Z',
            },
          ],
        },
      },
      _ => {'success': true, 'data': <String, dynamic>{}},
    };
  }
}

class _PresetAuthSessionNotifier extends TestAuthSessionNotifier {
  _PresetAuthSessionNotifier(this.initial);

  final AuthSessionState initial;

  @override
  AuthSessionState build() => initial;
}
