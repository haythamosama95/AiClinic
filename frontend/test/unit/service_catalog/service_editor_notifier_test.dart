<<<<<<< HEAD
=======
import 'dart:async';

import 'package:ai_clinic/core/rpc/rpc_result.dart';
>>>>>>> master
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/service_catalog/data/service_catalog_repository.dart';
import 'package:ai_clinic/features/service_catalog/domain/global_status.dart';
import 'package:ai_clinic/features/service_catalog/domain/pending_branch_configuration.dart';
import 'package:ai_clinic/features/billing/domain/money.dart';
import 'package:ai_clinic/features/service_catalog/domain/service_promotion.dart';
import 'package:ai_clinic/features/service_catalog/presentation/providers/service_editor_notifier.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../helpers/auth_test_support.dart';
import '../../support/fake_postgrest_rpc.dart';

void main() {
  group('ServiceEditorNotifier', () {
<<<<<<< HEAD
=======
    test('build returns empty state when user lacks editor permission', () async {
      final container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(
            () => _PresetAuthSessionNotifier(
              AuthSessionState(
                status: AuthSessionStatus.authenticated,
                context: sampleAuthSessionContext(role: StaffRole.receptionist, permissions: {'services.view'}),
              ),
            ),
          ),
          serviceCatalogRepositoryProvider.overrideWithValue(ServiceCatalogRepository(_ServiceCatalogRpcClient())),
        ],
      );
      addTearDown(container.dispose);

      final state = await container.read(serviceEditorProvider('service-1').future);
      expect(state.detail, isNull);
      expect(state.isSaving, isFalse);
    });

    test('build loads detail for authorized user with serviceId', () async {
      final rpcClient = _ServiceCatalogRpcClient();
      final container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(
            () => _PresetAuthSessionNotifier(
              AuthSessionState(
                status: AuthSessionStatus.authenticated,
                context: sampleAuthSessionContext(
                  role: StaffRole.administrator,
                  permissions: {'services.manage', 'services.view'},
                ),
              ),
            ),
          ),
          serviceCatalogRepositoryProvider.overrideWithValue(ServiceCatalogRepository(rpcClient)),
        ],
      );
      addTearDown(container.dispose);

      final state = await container.read(serviceEditorProvider('service-1').future);
      expect(rpcClient.calls, contains('get_service'));
      expect(state.detail?.service.name, 'Consultation');
      expect(state.detail?.service.id, 'service-1');
    });

    test('createService restores state on RPC failure', () async {
      final rpcClient = _ServiceCatalogRpcClient(
        rpcErrors: {
          'create_service': RpcFailure(
            const RpcResult(success: false, errorCode: 'RPC_ERROR', errorMessage: 'Create failed.'),
          ),
        },
      );
      final container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(
            () => _PresetAuthSessionNotifier(
              AuthSessionState(
                status: AuthSessionStatus.authenticated,
                context: sampleAuthSessionContext(
                  role: StaffRole.administrator,
                  permissions: {'services.manage', 'services.view'},
                ),
              ),
            ),
          ),
          serviceCatalogRepositoryProvider.overrideWithValue(ServiceCatalogRepository(rpcClient)),
        ],
      );
      addTearDown(container.dispose);

      await container.read(serviceEditorProvider(null).future);

      await expectLater(
        container
            .read(serviceEditorProvider(null).notifier)
            .createService(
              name: 'Consultation',
              defaultPrice: '200.00',
              globalStatus: GlobalStatus.active,
              assignAllBranches: false,
              selectedBranchIds: const {'branch-1'},
            ),
        throwsA(isA<RpcFailure>().having((error) => error.code, 'code', 'RPC_ERROR')),
      );

      final state = container.read(serviceEditorProvider(null));
      expect(state.value?.isSaving, isFalse);
      expect(state.value?.detail, isNull);
    });

    test('setBranchAssignment calls RPC and reloads detail', () async {
      final rpcClient = _ServiceCatalogRpcClient();
      final container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(
            () => _PresetAuthSessionNotifier(
              AuthSessionState(
                status: AuthSessionStatus.authenticated,
                context: sampleAuthSessionContext(
                  role: StaffRole.administrator,
                  permissions: {'services.manage', 'services.view'},
                ),
              ),
            ),
          ),
          serviceCatalogRepositoryProvider.overrideWithValue(ServiceCatalogRepository(rpcClient)),
        ],
      );
      addTearDown(container.dispose);

      await container.read(serviceEditorProvider('service-1').future);

      await container
          .read(serviceEditorProvider('service-1').notifier)
          .setBranchAssignment(branchIds: const ['branch-2'], assign: true);

      expect(rpcClient.calls, contains('set_service_branch_assignment'));
      expect(rpcClient.calls.last, 'get_service');
      expect(container.read(serviceEditorProvider('service-1')).value?.isSaving, isFalse);
    });

    test('setBranchAssignment throws when service not loaded', () async {
      final container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(
            () => _PresetAuthSessionNotifier(
              AuthSessionState(
                status: AuthSessionStatus.authenticated,
                context: sampleAuthSessionContext(
                  role: StaffRole.administrator,
                  permissions: {'services.manage', 'services.view'},
                ),
              ),
            ),
          ),
          serviceCatalogRepositoryProvider.overrideWithValue(ServiceCatalogRepository(_ServiceCatalogRpcClient())),
        ],
      );
      addTearDown(container.dispose);

      await container.read(serviceEditorProvider(null).future);

      await expectLater(
        container
            .read(serviceEditorProvider(null).notifier)
            .setBranchAssignment(branchIds: const ['branch-1'], assign: true),
        throwsA(isA<StateError>()),
      );
    });

    test('configureServiceBranch updates branch settings and reloads detail', () async {
      final rpcClient = _ServiceCatalogRpcClient();
      final container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(
            () => _PresetAuthSessionNotifier(
              AuthSessionState(
                status: AuthSessionStatus.authenticated,
                context: sampleAuthSessionContext(
                  role: StaffRole.administrator,
                  permissions: {'services.manage', 'services.view'},
                ),
              ),
            ),
          ),
          serviceCatalogRepositoryProvider.overrideWithValue(ServiceCatalogRepository(rpcClient)),
        ],
      );
      addTearDown(container.dispose);

      final initial = await container.read(serviceEditorProvider('service-1').future);
      final branch = initial.detail!.branches.first;

      await container
          .read(serviceEditorProvider('service-1').notifier)
          .configureServiceBranch(
            branchId: branch.branchId,
            expectedUpdatedAt: branch.updatedAt!,
            active: false,
            priceOverride: '175.00',
          );

      expect(rpcClient.calls, contains('configure_service_branch'));
      expect(rpcClient.calls.last, 'get_service');
      expect(container.read(serviceEditorProvider('service-1')).value?.isSaving, isFalse);
    });

    test('configureServiceBranch on STALE_SERVICE_BRANCH reloads detail then rethrows', () async {
      final rpcClient = _ServiceCatalogRpcClient(
        rpcErrors: {
          'configure_service_branch': RpcFailure(
            const RpcResult(success: false, errorCode: 'STALE_SERVICE_BRANCH', errorMessage: 'Stale branch.'),
          ),
        },
      );
      final container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(
            () => _PresetAuthSessionNotifier(
              AuthSessionState(
                status: AuthSessionStatus.authenticated,
                context: sampleAuthSessionContext(
                  role: StaffRole.administrator,
                  permissions: {'services.manage', 'services.view'},
                ),
              ),
            ),
          ),
          serviceCatalogRepositoryProvider.overrideWithValue(ServiceCatalogRepository(rpcClient)),
        ],
      );
      addTearDown(container.dispose);

      final initial = await container.read(serviceEditorProvider('service-1').future);
      final branch = initial.detail!.branches.first;
      final getServiceCallsBefore = rpcClient.calls.where((call) => call == 'get_service').length;

      await expectLater(
        container
            .read(serviceEditorProvider('service-1').notifier)
            .configureServiceBranch(
              branchId: branch.branchId,
              expectedUpdatedAt: branch.updatedAt!,
              active: true,
            ),
        throwsA(isA<RpcFailure>().having((error) => error.code, 'code', 'STALE_SERVICE_BRANCH')),
      );

      expect(rpcClient.calls.where((call) => call == 'get_service').length, greaterThan(getServiceCallsBefore));
      final state = container.read(serviceEditorProvider('service-1'));
      expect(state.value?.isSaving, isFalse);
      expect(state.value?.detail, isNotNull);
    });

    test('setServicePromotion sets promotion and reloads detail', () async {
      final rpcClient = _ServiceCatalogRpcClient();
      final container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(
            () => _PresetAuthSessionNotifier(
              AuthSessionState(
                status: AuthSessionStatus.authenticated,
                context: sampleAuthSessionContext(
                  role: StaffRole.administrator,
                  permissions: {'services.manage', 'services.view'},
                ),
              ),
            ),
          ),
          serviceCatalogRepositoryProvider.overrideWithValue(ServiceCatalogRepository(rpcClient)),
        ],
      );
      addTearDown(container.dispose);

      final initial = await container.read(serviceEditorProvider('service-1').future);
      final branch = initial.detail!.branches.first;

      await container
          .read(serviceEditorProvider('service-1').notifier)
          .setServicePromotion(
            branchId: branch.branchId,
            expectedUpdatedAt: branch.updatedAt!,
            promotionPrice: '90.00',
            startDate: DateTime(2026, 2, 1),
            endDate: DateTime(2026, 2, 28),
          );

      expect(rpcClient.calls, contains('set_service_promotion'));
      expect(rpcClient.calls.last, 'get_service');
    });

    test('clearServicePromotion clears promotion via setServicePromotion', () async {
      final rpcClient = _ServiceCatalogRpcClient();
      final container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(
            () => _PresetAuthSessionNotifier(
              AuthSessionState(
                status: AuthSessionStatus.authenticated,
                context: sampleAuthSessionContext(
                  role: StaffRole.administrator,
                  permissions: {'services.manage', 'services.view'},
                ),
              ),
            ),
          ),
          serviceCatalogRepositoryProvider.overrideWithValue(ServiceCatalogRepository(rpcClient)),
        ],
      );
      addTearDown(container.dispose);

      final initial = await container.read(serviceEditorProvider('service-1').future);
      final branch = initial.detail!.branches.first;

      await container
          .read(serviceEditorProvider('service-1').notifier)
          .clearServicePromotion(branchId: branch.branchId, expectedUpdatedAt: branch.updatedAt!);

      expect(rpcClient.calls, contains('set_service_promotion'));
    });

    test('setGlobalStatus updates status and reloads detail', () async {
      final rpcClient = _ServiceCatalogRpcClient();
      final container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(
            () => _PresetAuthSessionNotifier(
              AuthSessionState(
                status: AuthSessionStatus.authenticated,
                context: sampleAuthSessionContext(
                  role: StaffRole.administrator,
                  permissions: {'services.manage', 'services.view'},
                ),
              ),
            ),
          ),
          serviceCatalogRepositoryProvider.overrideWithValue(ServiceCatalogRepository(rpcClient)),
        ],
      );
      addTearDown(container.dispose);

      await container.read(serviceEditorProvider('service-1').future);

      await container.read(serviceEditorProvider('service-1').notifier).setGlobalStatus(GlobalStatus.inactive);

      expect(rpcClient.calls, contains('set_service_global_status'));
      expect(rpcClient.calls.last, 'get_service');
      expect(
        container.read(serviceEditorProvider('service-1')).value?.detail?.service.globalStatus,
        GlobalStatus.inactive,
      );
    });

    test('updateService on STALE_SERVICE reloads detail then rethrows', () async {
      final rpcClient = _ServiceCatalogRpcClient(
        rpcErrors: {
          'update_service': RpcFailure(
            const RpcResult(success: false, errorCode: 'STALE_SERVICE', errorMessage: 'Stale service.'),
          ),
        },
      );
      final container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(
            () => _PresetAuthSessionNotifier(
              AuthSessionState(
                status: AuthSessionStatus.authenticated,
                context: sampleAuthSessionContext(
                  role: StaffRole.administrator,
                  permissions: {'services.manage', 'services.view'},
                ),
              ),
            ),
          ),
          serviceCatalogRepositoryProvider.overrideWithValue(ServiceCatalogRepository(rpcClient)),
        ],
      );
      addTearDown(container.dispose);

      await container.read(serviceEditorProvider('service-1').future);
      final getServiceCallsBefore = rpcClient.calls.where((call) => call == 'get_service').length;

      await expectLater(
        container
            .read(serviceEditorProvider('service-1').notifier)
            .updateService(
              name: 'General Consultation',
              defaultPrice: '220.00',
              globalStatus: GlobalStatus.inactive,
              assignAllBranches: false,
              selectedBranchIds: const {'branch-1'},
              allBranchIds: const ['branch-1', 'branch-2'],
            ),
        throwsA(isA<RpcFailure>().having((error) => error.code, 'code', 'STALE_SERVICE')),
      );

      expect(rpcClient.calls.where((call) => call == 'get_service').length, greaterThan(getServiceCallsBefore));
      final state = container.read(serviceEditorProvider('service-1'));
      expect(state.value?.isSaving, isFalse);
      expect(state.value?.detail, isNotNull);
    });

>>>>>>> master
    test('createService calls RPCs and stores loaded detail', () async {
      final rpcClient = _ServiceCatalogRpcClient();
      final container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(
            () => _PresetAuthSessionNotifier(
              AuthSessionState(
                status: AuthSessionStatus.authenticated,
                context: sampleAuthSessionContext(
                  role: StaffRole.administrator,
                  permissions: {'services.manage', 'services.view'},
                ),
              ),
            ),
          ),
          serviceCatalogRepositoryProvider.overrideWithValue(ServiceCatalogRepository(rpcClient)),
        ],
      );
      addTearDown(container.dispose);

      final serviceId = await container
          .read(serviceEditorProvider(null).notifier)
          .createService(
            name: 'Consultation',
            defaultPrice: '200.00',
            globalStatus: GlobalStatus.active,
            assignAllBranches: false,
            selectedBranchIds: const {'branch-1', 'branch-2'},
          );

      expect(serviceId, 'service-1');
      expect(rpcClient.calls, ['create_service', 'get_service']);
      final state = container.read(serviceEditorProvider(null));
      expect(state.value?.detail?.service.name, 'Consultation');
    });

    test('createService applies pending branch overrides and promotions', () async {
      final rpcClient = _ServiceCatalogRpcClient();
      final container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(
            () => _PresetAuthSessionNotifier(
              AuthSessionState(
                status: AuthSessionStatus.authenticated,
                context: sampleAuthSessionContext(
                  role: StaffRole.administrator,
                  permissions: {'services.manage', 'services.view'},
                ),
              ),
            ),
          ),
          serviceCatalogRepositoryProvider.overrideWithValue(ServiceCatalogRepository(rpcClient)),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(serviceEditorProvider(null).notifier)
          .createService(
            name: 'Consultation',
            defaultPrice: '200.00',
            globalStatus: GlobalStatus.active,
            assignAllBranches: false,
            selectedBranchIds: const {'branch-1'},
            pendingBranchConfigs: [
              PendingBranchConfiguration(
                branchId: 'branch-1',
                priceOverride: '150.00',
                promotion: ServicePromotion(
                  price: Money.parse('100.00'),
                  startDate: DateTime(2026, 1, 1),
                  endDate: DateTime(2026, 1, 31),
                ),
              ),
            ],
          );

      expect(rpcClient.calls, contains('configure_service_branch'));
      expect(rpcClient.calls, contains('set_service_promotion'));
    });

    test('updateService calls update RPC and reloads detail', () async {
      final rpcClient = _ServiceCatalogRpcClient();
      final container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(
            () => _PresetAuthSessionNotifier(
              AuthSessionState(
                status: AuthSessionStatus.authenticated,
                context: sampleAuthSessionContext(
                  role: StaffRole.administrator,
                  permissions: {'services.manage', 'services.view'},
                ),
              ),
            ),
          ),
          serviceCatalogRepositoryProvider.overrideWithValue(ServiceCatalogRepository(rpcClient)),
        ],
      );
      addTearDown(container.dispose);

      await container.read(serviceEditorProvider('service-1').future);

      await container
          .read(serviceEditorProvider('service-1').notifier)
          .updateService(
            name: 'General Consultation',
            defaultPrice: '220.00',
            globalStatus: GlobalStatus.inactive,
            assignAllBranches: false,
            selectedBranchIds: const {'branch-1'},
            allBranchIds: const ['branch-1', 'branch-2'],
          );

      expect(rpcClient.calls, contains('update_service'));
      expect(rpcClient.calls.last, 'get_service');
      final state = container.read(serviceEditorProvider('service-1'));
      expect(state.value?.detail?.service.name, 'General Consultation');
    });

<<<<<<< HEAD
=======
    test('updateService reloads detail when provider state was disposed', () async {
      final rpcClient = _ServiceCatalogRpcClient();
      final container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(
            () => _PresetAuthSessionNotifier(
              AuthSessionState(
                status: AuthSessionStatus.authenticated,
                context: sampleAuthSessionContext(
                  role: StaffRole.administrator,
                  permissions: {'services.manage', 'services.view'},
                ),
              ),
            ),
          ),
          serviceCatalogRepositoryProvider.overrideWithValue(ServiceCatalogRepository(rpcClient)),
        ],
      );
      addTearDown(container.dispose);

      final subscription = container.listen(serviceEditorProvider('service-1'), (_, _) {});
      await container.read(serviceEditorProvider('service-1').future);
      subscription.close();

      await container
          .read(serviceEditorProvider('service-1').notifier)
          .updateService(
            name: 'General Consultation',
            defaultPrice: '220.00',
            globalStatus: GlobalStatus.inactive,
            assignAllBranches: false,
            selectedBranchIds: const {'branch-1'},
            allBranchIds: const ['branch-1', 'branch-2'],
          );

      expect(rpcClient.calls.where((call) => call == 'get_service').length, greaterThanOrEqualTo(2));
      expect(rpcClient.calls, contains('update_service'));
      final state = container.read(serviceEditorProvider('service-1'));
      expect(state.value?.detail?.service.name, 'General Consultation');
    });

>>>>>>> master
    test('softDeleteService calls soft delete RPC', () async {
      final rpcClient = _ServiceCatalogRpcClient();
      final container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(
            () => _PresetAuthSessionNotifier(
              AuthSessionState(
                status: AuthSessionStatus.authenticated,
                context: sampleAuthSessionContext(
                  role: StaffRole.administrator,
                  permissions: {'services.manage', 'services.view'},
                ),
              ),
            ),
          ),
          serviceCatalogRepositoryProvider.overrideWithValue(ServiceCatalogRepository(rpcClient)),
        ],
      );
      addTearDown(container.dispose);

      await container.read(serviceEditorProvider('service-1').future);
      await container.read(serviceEditorProvider('service-1').notifier).softDeleteService();

      expect(rpcClient.calls, contains('soft_delete_service'));
      final state = container.read(serviceEditorProvider('service-1'));
      expect(state.value?.detail, isNull);
    });
<<<<<<< HEAD
=======

    test('softDeleteService skips state updates when provider is disposed during load', () async {
      final rpcClient = _DelayedGetServiceRpcClient();
      final container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(
            () => _PresetAuthSessionNotifier(
              AuthSessionState(
                status: AuthSessionStatus.authenticated,
                context: sampleAuthSessionContext(
                  role: StaffRole.administrator,
                  permissions: {'services.manage', 'services.view'},
                ),
              ),
            ),
          ),
          serviceCatalogRepositoryProvider.overrideWithValue(ServiceCatalogRepository(rpcClient)),
        ],
      );
      addTearDown(container.dispose);

      final subscription = container.listen(serviceEditorProvider('service-1'), (_, _) {});
      final notifier = container.read(serviceEditorProvider('service-1').notifier);
      final deleteFuture = notifier.softDeleteService();
      subscription.close();
      await rpcClient.releaseGetService();

      await expectLater(deleteFuture, completes);
      expect(rpcClient.calls, contains('soft_delete_service'));
    });
>>>>>>> master
  });
}

class _ServiceCatalogRpcClient extends RpcCaptureSupabaseClient {
<<<<<<< HEAD
=======
  _ServiceCatalogRpcClient({this.rpcErrors = const {}});

  final Map<String, RpcFailure> rpcErrors;
>>>>>>> master
  final List<String> calls = <String>[];
  int _getServiceCalls = 0;

  @override
  PostgrestFilterBuilder<T> rpc<T>(String fn, {Map<String, dynamic>? params, dynamic get = false}) {
    calls.add(fn);
<<<<<<< HEAD
    return FakePostgrestRpc(_payloadFor(fn)) as PostgrestFilterBuilder<T>;
  }

  Map<String, dynamic> _payloadFor(String fn) {
=======
    final failure = rpcErrors[fn];
    if (failure != null) {
      return FakePostgrestRpc({
        'success': false,
        'error_code': failure.code,
        'error_message': failure.message,
      }) as PostgrestFilterBuilder<T>;
    }
    return FakePostgrestRpc(_payloadFor(fn, params)) as PostgrestFilterBuilder<T>;
  }

  Map<String, dynamic> _payloadFor(String fn, Map<String, dynamic>? params) {
>>>>>>> master
    return switch (fn) {
      'create_service' => {
        'success': true,
        'data': {
          'service_id': 'service-1',
          'assigned_branch_ids': ['branch-1', 'branch-2'],
        },
      },
      'get_service' => _getServicePayload(),
      'configure_service_branch' => {
        'success': true,
        'data': {'service_branch_id': 'sb-1', 'updated_at': '2026-01-02T10:00:00.000Z'},
      },
      'set_service_promotion' => {
        'success': true,
        'data': {'service_branch_id': 'sb-1', 'has_promotion': true, 'updated_at': '2026-01-03T10:00:00.000Z'},
      },
<<<<<<< HEAD
=======
      'set_service_branch_assignment' => {
        'success': true,
        'data': _branchAssignmentPayload(params),
      },
      'set_service_global_status' => {
        'success': true,
        'data': {
          'service_id': 'service-1',
          'global_status': 'inactive',
          'updated_at': '2026-01-04T10:00:00.000Z',
        },
      },
>>>>>>> master
      'update_service' => {
        'success': true,
        'data': {'service_id': 'service-1', 'updated_at': '2026-01-02T10:00:00.000Z'},
      },
      'soft_delete_service' => {
        'success': true,
        'data': {'service_id': 'service-1'},
      },
      _ => {'success': true, 'data': <String, dynamic>{}},
    };
  }

<<<<<<< HEAD
=======
  Map<String, dynamic> _branchAssignmentPayload(Map<String, dynamic>? params) {
    final branchIds = params?['p_branch_ids'];
    final ids = branchIds is List ? List<String>.from(branchIds.map((id) => id.toString())) : <String>['branch-2'];
    if (params?['p_assign'] == true) {
      return {'assigned_branch_ids': ids};
    }
    return {'unassigned_branch_ids': ids};
  }

>>>>>>> master
  Map<String, dynamic> _getServicePayload() {
    final call = _getServiceCalls++;
    final updated = call > 0;
    return {
      'success': true,
      'data': {
        'service': {
          'id': 'service-1',
          'name': updated ? 'General Consultation' : 'Consultation',
          'default_price': updated ? '220.00' : '200.00',
          'global_status': updated ? 'inactive' : 'active',
          'created_at': '2026-01-01T10:00:00.000Z',
          'updated_at': '2026-01-02T10:00:00.000Z',
        },
        'branches': [
          {
            'service_branch_id': 'sb-1',
            'branch_id': 'branch-1',
            'status': 'active',
            'price_override': null,
            'promotion_price': null,
            'promotion_start_date': null,
            'promotion_end_date': null,
            'updated_at': '2026-01-01T10:00:00.000Z',
          },
        ],
      },
    };
  }
}

<<<<<<< HEAD
=======
class _DelayedGetServiceRpcClient extends _ServiceCatalogRpcClient {
  Completer<void>? _getServiceGate;

  Future<void> releaseGetService() {
    final gate = _getServiceGate;
    if (gate != null && !gate.isCompleted) {
      gate.complete();
    }
    return gate?.future ?? Future<void>.value();
  }

  @override
  PostgrestFilterBuilder<T> rpc<T>(String fn, {Map<String, dynamic>? params, dynamic get = false}) {
    if (fn == 'get_service') {
      _getServiceGate = Completer<void>();
      return _DelayedPostgrestRpc(_getServiceGate!.future, _getServicePayload()) as PostgrestFilterBuilder<T>;
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

>>>>>>> master
class _PresetAuthSessionNotifier extends TestAuthSessionNotifier {
  _PresetAuthSessionNotifier(this.initial);

  final AuthSessionState initial;

  @override
  AuthSessionState build() => initial;
}
