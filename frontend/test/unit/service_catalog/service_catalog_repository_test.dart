import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/service_catalog/data/service_catalog_repository.dart';
import 'package:ai_clinic/features/service_catalog/domain/effective_price.dart';
import 'package:ai_clinic/features/service_catalog/domain/global_status.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/service_catalog_rpc_test_client.dart';

const _serviceId = 'service-1';
const _branchId = 'branch-1';
const _branchId2 = 'branch-2';
const _serviceBranchId = 'sb-1';
const _invoiceId = 'invoice-1';
const _itemId = 'item-1';
const _updatedAt = '2026-01-02T10:00:00.000Z';

void main() {
  late ServiceCatalogRpcTestClient client;
  late ServiceCatalogRepository repo;

  setUp(() {
    client = ServiceCatalogRpcTestClient();
    repo = ServiceCatalogRepository(client);
  });

  group('ServiceCatalogRepository createService', () {
    test('returns service id and assigned branch ids on success', () async {
      final result = await repo.createService(
        name: 'Consultation',
        defaultPrice: '150.00',
        globalStatus: GlobalStatus.active,
        assignAllBranches: false,
        branchIds: [_branchId],
      );

      expect(result.serviceId, _serviceId);
      expect(result.assignedBranchIds, [_branchId]);
      expect(client.lastFunction, 'create_service');
      expect(client.lastParams?['p_name'], 'Consultation');
      expect(client.lastParams?['p_default_price'], '150.00');
      expect(client.lastParams?['p_global_status'], 'active');
      expect(client.lastParams?['p_assign_all_branches'], isFalse);
      expect(client.lastParams?['p_branch_ids'], [_branchId]);
    });

    test('trims name and defaultPrice', () async {
      await repo.createService(
        name: '  Consultation  ',
        defaultPrice: '  150.00  ',
        globalStatus: GlobalStatus.active,
        assignAllBranches: false,
        branchIds: const [],
      );

      expect(client.lastParams?['p_name'], 'Consultation');
      expect(client.lastParams?['p_default_price'], '150.00');
    });

    test('assignAllBranches clears branch_ids', () async {
      await repo.createService(
        name: 'Consultation',
        defaultPrice: '150.00',
        globalStatus: GlobalStatus.active,
        assignAllBranches: true,
        branchIds: [_branchId],
      );

      expect(client.lastParams?['p_assign_all_branches'], isTrue);
      expect(client.lastParams?['p_branch_ids'], isEmpty);
    });

    test('rejects empty name before RPC', () {
      expect(
        () => repo.createService(
          name: '   ',
          defaultPrice: '150.00',
          globalStatus: GlobalStatus.active,
          assignAllBranches: false,
        ),
        throwsA(isA<RpcFailure>().having((error) => error.code, 'code', 'INVALID_INPUT')),
      );
      expect(client.rpcLog, isEmpty);
    });

    test('rejects empty defaultPrice before RPC', () {
      expect(
        () => repo.createService(
          name: 'Consultation',
          defaultPrice: '   ',
          globalStatus: GlobalStatus.active,
          assignAllBranches: false,
        ),
        throwsA(isA<RpcFailure>().having((error) => error.code, 'code', 'INVALID_INPUT')),
      );
      expect(client.rpcLog, isEmpty);
    });

    test('throws StateError when service_id is missing', () async {
      client = ServiceCatalogRpcTestClient(
        rpcResults: {
          'create_service': {'success': true, 'data': null},
        },
      );
      repo = ServiceCatalogRepository(client);

      await expectLater(
        repo.createService(
          name: 'Consultation',
          defaultPrice: '150.00',
          globalStatus: GlobalStatus.active,
          assignAllBranches: false,
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('ServiceCatalogRepository getService', () {
    test('returns parsed ServiceDetail on success', () async {
      final detail = await repo.getService(serviceId: '  $_serviceId  ');

      expect(detail.service.id, _serviceId);
      expect(detail.service.name, 'Consultation');
      expect(detail.branches, hasLength(1));
      expect(detail.branches.first.branchId, _branchId);
      expect(client.lastFunction, 'get_service');
      expect(client.lastParams?['p_service_id'], _serviceId);
    });

    test('rejects empty serviceId before RPC', () {
      expect(
        () => repo.getService(serviceId: '   '),
        throwsA(isA<RpcFailure>().having((error) => error.code, 'code', 'INVALID_INPUT')),
      );
      expect(client.rpcLog, isEmpty);
    });

    test('throws StateError when response shape is unparseable', () async {
      client = ServiceCatalogRpcTestClient(
        rpcResults: {
          'get_service': {'success': true, 'data': {}},
        },
      );
      repo = ServiceCatalogRepository(client);

      await expectLater(
        repo.getService(serviceId: _serviceId),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('ServiceCatalogRepository setBranchAssignment', () {
    test('returns assigned branch ids on assign', () async {
      final ids = await repo.setBranchAssignment(
        serviceId: _serviceId,
        branchIds: [_branchId],
        assign: true,
      );

      expect(ids, [_branchId]);
      expect(client.lastFunction, 'set_service_branch_assignment');
      expect(client.lastParams?['p_service_id'], _serviceId);
      expect(client.lastParams?['p_branch_ids'], [_branchId]);
      expect(client.lastParams?['p_assign'], isTrue);
    });

    test('returns unassigned branch ids on unassign', () async {
      client = ServiceCatalogRpcTestClient(
        rpcResults: {
          'set_service_branch_assignment': {
            'success': true,
            'data': {'unassigned_branch_ids': [_branchId2]},
          },
        },
      );
      repo = ServiceCatalogRepository(client);

      final ids = await repo.setBranchAssignment(
        serviceId: _serviceId,
        branchIds: [_branchId2],
        assign: false,
      );

      expect(ids, [_branchId2]);
      expect(client.lastParams?['p_assign'], isFalse);
    });

    test('rejects empty serviceId before RPC', () {
      expect(
        () => repo.setBranchAssignment(
          serviceId: '   ',
          branchIds: [_branchId],
          assign: true,
        ),
        throwsA(isA<RpcFailure>().having((error) => error.code, 'code', 'INVALID_INPUT')),
      );
      expect(client.rpcLog, isEmpty);
    });

    test('rejects empty branchIds before RPC', () {
      expect(
        () => repo.setBranchAssignment(
          serviceId: _serviceId,
          branchIds: const [],
          assign: true,
        ),
        throwsA(isA<RpcFailure>().having((error) => error.code, 'code', 'INVALID_INPUT')),
      );
      expect(client.rpcLog, isEmpty);
    });
  });

  group('ServiceCatalogRepository configureServiceBranch', () {
    final expectedUpdatedAt = DateTime.utc(2026, 1, 2, 10);

    test('returns service branch id and updatedAt on success', () async {
      final result = await repo.configureServiceBranch(
        serviceId: '  $_serviceId  ',
        branchId: '  $_branchId  ',
        expectedUpdatedAt: expectedUpdatedAt,
        status: '  active  ',
        priceOverride: '  175.00  ',
      );

      expect(result.serviceBranchId, _serviceBranchId);
      expect(result.updatedAt, DateTime.parse(_updatedAt));
      expect(client.lastFunction, 'configure_service_branch');
      expect(client.lastParams?['p_service_id'], _serviceId);
      expect(client.lastParams?['p_branch_id'], _branchId);
      expect(client.lastParams?['p_expected_updated_at'], expectedUpdatedAt.toUtc().toIso8601String());
      expect(client.lastParams?['p_status'], 'active');
      expect(client.lastParams?['p_price_override'], '175.00');
    });

    test('rejects empty serviceId before RPC', () {
      expect(
        () => repo.configureServiceBranch(
          serviceId: '   ',
          branchId: _branchId,
          expectedUpdatedAt: expectedUpdatedAt,
          status: 'active',
        ),
        throwsA(isA<RpcFailure>().having((error) => error.code, 'code', 'INVALID_INPUT')),
      );
      expect(client.rpcLog, isEmpty);
    });

    test('rejects empty branchId before RPC', () {
      expect(
        () => repo.configureServiceBranch(
          serviceId: _serviceId,
          branchId: '   ',
          expectedUpdatedAt: expectedUpdatedAt,
          status: 'active',
        ),
        throwsA(isA<RpcFailure>().having((error) => error.code, 'code', 'INVALID_INPUT')),
      );
      expect(client.rpcLog, isEmpty);
    });

    test('rejects empty status before RPC', () {
      expect(
        () => repo.configureServiceBranch(
          serviceId: _serviceId,
          branchId: _branchId,
          expectedUpdatedAt: expectedUpdatedAt,
          status: '   ',
        ),
        throwsA(isA<RpcFailure>().having((error) => error.code, 'code', 'INVALID_INPUT')),
      );
      expect(client.rpcLog, isEmpty);
    });

    test('throws StateError when response shape is malformed', () async {
      client = ServiceCatalogRpcTestClient(
        rpcResults: {
          'configure_service_branch': {'success': true, 'data': null},
        },
      );
      repo = ServiceCatalogRepository(client);

      await expectLater(
        repo.configureServiceBranch(
          serviceId: _serviceId,
          branchId: _branchId,
          expectedUpdatedAt: expectedUpdatedAt,
          status: 'active',
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('ServiceCatalogRepository setServicePromotion', () {
    final expectedUpdatedAt = DateTime.utc(2026, 1, 2, 10);
    final startDate = DateTime(2026, 8, 1);
    final endDate = DateTime(2026, 8, 31);

    test('sets promotion on success', () async {
      final result = await repo.setServicePromotion(
        serviceId: _serviceId,
        branchId: _branchId,
        expectedUpdatedAt: expectedUpdatedAt,
        promotionPrice: '  120.00  ',
        startDate: startDate,
        endDate: endDate,
      );

      expect(result.serviceBranchId, _serviceBranchId);
      expect(result.hasPromotion, isTrue);
      expect(result.updatedAt, DateTime.parse('2026-01-03T10:00:00.000Z'));
      expect(client.lastFunction, 'set_service_promotion');
      expect(client.lastParams?['p_promotion_price'], '120.00');
      expect(client.lastParams?['p_start_date'], '2026-08-01');
      expect(client.lastParams?['p_end_date'], '2026-08-31');
      expect(client.lastParams?['p_expected_updated_at'], expectedUpdatedAt.toUtc().toIso8601String());
    });

    test('clears promotion when all promo fields are null', () async {
      client = ServiceCatalogRpcTestClient(
        rpcResults: {
          'set_service_promotion': {
            'success': true,
            'data': {
              'service_branch_id': _serviceBranchId,
              'has_promotion': false,
              'updated_at': '2026-01-03T10:00:00.000Z',
            },
          },
        },
      );
      repo = ServiceCatalogRepository(client);

      final result = await repo.setServicePromotion(
        serviceId: _serviceId,
        branchId: _branchId,
        expectedUpdatedAt: expectedUpdatedAt,
      );

      expect(result.hasPromotion, isFalse);
      expect(client.lastParams?['p_promotion_price'], isNull);
      expect(client.lastParams?['p_start_date'], isNull);
      expect(client.lastParams?['p_end_date'], isNull);
    });

    test('rejects incomplete promotion before RPC', () {
      expect(
        () => repo.setServicePromotion(
          serviceId: _serviceId,
          branchId: _branchId,
          expectedUpdatedAt: expectedUpdatedAt,
          promotionPrice: '120.00',
        ),
        throwsA(isA<RpcFailure>().having((error) => error.code, 'code', 'PROMO_INCOMPLETE')),
      );
      expect(client.rpcLog, isEmpty);
    });

    test('throws StateError when response shape is malformed', () async {
      client = ServiceCatalogRpcTestClient(
        rpcResults: {
          'set_service_promotion': {'success': true, 'data': {}},
        },
      );
      repo = ServiceCatalogRepository(client);

      await expectLater(
        repo.setServicePromotion(
          serviceId: _serviceId,
          branchId: _branchId,
          expectedUpdatedAt: expectedUpdatedAt,
          promotionPrice: '120.00',
          startDate: startDate,
          endDate: endDate,
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('ServiceCatalogRepository resolveEffectivePrice', () {
    test('returns eligible price without onDate', () async {
      final eligibility = await repo.resolveEffectivePrice(
        serviceId: '  $_serviceId  ',
        branchId: '  $_branchId  ',
      );

      expect(eligibility.eligible, isTrue);
      expect(eligibility.price?.unitPrice.toString(), '150.00');
      expect(eligibility.price?.appliedRule, AppliedPriceRule.defaultPrice);
      expect(client.lastFunction, 'resolve_effective_service_price');
      expect(client.lastParams?['p_service_id'], _serviceId);
      expect(client.lastParams?['p_branch_id'], _branchId);
      expect(client.lastParams?.containsKey('p_on_date'), isFalse);
    });

    test('forwards formatted onDate', () async {
      final onDate = DateTime(2026, 7, 15);

      await repo.resolveEffectivePrice(
        serviceId: _serviceId,
        branchId: _branchId,
        onDate: onDate,
      );

      expect(client.lastParams?['p_on_date'], '2026-07-15');
    });

    test('rejects empty serviceId before RPC', () {
      expect(
        () => repo.resolveEffectivePrice(
          serviceId: '   ',
          branchId: _branchId,
        ),
        throwsA(isA<RpcFailure>().having((error) => error.code, 'code', 'INVALID_INPUT')),
      );
      expect(client.rpcLog, isEmpty);
    });

    test('rejects empty branchId before RPC', () {
      expect(
        () => repo.resolveEffectivePrice(
          serviceId: _serviceId,
          branchId: '   ',
        ),
        throwsA(isA<RpcFailure>().having((error) => error.code, 'code', 'INVALID_INPUT')),
      );
      expect(client.rpcLog, isEmpty);
    });
  });

  group('ServiceCatalogRepository searchEligibleServices', () {
    test('parses eligible service items and skips invalid rows', () async {
      final items = await repo.searchEligibleServices(
        branchId: '  $_branchId  ',
        query: '  consult  ',
      );

      expect(items, hasLength(1));
      expect(items.first.serviceId, _serviceId);
      expect(items.first.name, 'Consultation');
      expect(client.lastFunction, 'search_eligible_services');
      expect(client.lastParams?['p_branch_id'], _branchId);
      expect(client.lastParams?['p_query'], 'consult');
      expect(client.lastParams?['p_limit'], 20);
    });

    test('forwards onDate when provided', () async {
      final onDate = DateTime(2026, 7, 20);

      await repo.searchEligibleServices(
        branchId: _branchId,
        onDate: onDate,
      );

      expect(client.lastParams?['p_on_date'], '2026-07-20');
    });

    test('rejects empty branchId before RPC', () {
      expect(
        () => repo.searchEligibleServices(branchId: '   '),
        throwsA(isA<RpcFailure>().having((error) => error.code, 'code', 'INVALID_INPUT')),
      );
      expect(client.rpcLog, isEmpty);
    });

    test('returns empty list when items is not a list', () async {
      client = ServiceCatalogRpcTestClient(
        rpcResults: {
          'search_eligible_services': {
            'success': true,
            'data': {'items': 'not-a-list'},
          },
        },
      );
      repo = ServiceCatalogRepository(client);

      final items = await repo.searchEligibleServices(branchId: _branchId);

      expect(items, isEmpty);
    });

    test('returns empty list when items key is absent', () async {
      client = ServiceCatalogRpcTestClient(
        rpcResults: {
          'search_eligible_services': {'success': true, 'data': {}},
        },
      );
      repo = ServiceCatalogRepository(client);

      final items = await repo.searchEligibleServices(branchId: _branchId);

      expect(items, isEmpty);
    });
  });

  group('ServiceCatalogRepository addInvoiceItemFromService', () {
    final expectedUpdatedAt = DateTime.utc(2026, 1, 2, 10);

    test('returns item details on success', () async {
      final result = await repo.addInvoiceItemFromService(
        invoiceId: '  $_invoiceId  ',
        expectedUpdatedAt: expectedUpdatedAt,
        serviceId: '  $_serviceId  ',
      );

      expect(result.itemId, _itemId);
      expect(result.quantity, '1');
      expect(result.unitPrice, '200.00');
      expect(result.appliedRule, 'default');
      expect(client.lastFunction, 'add_invoice_item_from_service');
      expect(client.lastParams?['p_invoice_id'], _invoiceId);
      expect(client.lastParams?['p_service_id'], _serviceId);
      expect(client.lastParams?['p_expected_updated_at'], expectedUpdatedAt.toUtc().toIso8601String());
    });

    test('rejects empty invoiceId before RPC', () {
      expect(
        () => repo.addInvoiceItemFromService(
          invoiceId: '   ',
          expectedUpdatedAt: expectedUpdatedAt,
          serviceId: _serviceId,
        ),
        throwsA(isA<RpcFailure>().having((error) => error.code, 'code', 'INVALID_INPUT')),
      );
      expect(client.rpcLog, isEmpty);
    });

    test('throws StateError when response shape is malformed', () async {
      client = ServiceCatalogRpcTestClient(
        rpcResults: {
          'add_invoice_item_from_service': {
            'success': true,
            'data': {'item_id': _itemId},
          },
        },
      );
      repo = ServiceCatalogRepository(client);

      await expectLater(
        repo.addInvoiceItemFromService(
          invoiceId: _invoiceId,
          expectedUpdatedAt: expectedUpdatedAt,
          serviceId: _serviceId,
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('ServiceCatalogRepository updateService', () {
    final expectedUpdatedAt = DateTime.utc(2026, 1, 2, 10);

    test('returns updated service id and timestamp on success', () async {
      final result = await repo.updateService(
        serviceId: '  $_serviceId  ',
        expectedUpdatedAt: expectedUpdatedAt,
        name: '  Updated name  ',
        defaultPrice: '  200.00  ',
        globalStatus: GlobalStatus.inactive,
      );

      expect(result.serviceId, _serviceId);
      expect(result.updatedAt, DateTime.parse(_updatedAt));
      expect(client.lastFunction, 'update_service');
      expect(client.lastParams?['p_name'], 'Updated name');
      expect(client.lastParams?['p_default_price'], '200.00');
      expect(client.lastParams?['p_global_status'], 'inactive');
      expect(client.lastParams?['p_expected_updated_at'], expectedUpdatedAt.toUtc().toIso8601String());
    });

    test('rejects empty name before RPC', () {
      expect(
        () => repo.updateService(
          serviceId: _serviceId,
          expectedUpdatedAt: expectedUpdatedAt,
          name: '   ',
          defaultPrice: '200.00',
          globalStatus: GlobalStatus.active,
        ),
        throwsA(isA<RpcFailure>().having((error) => error.code, 'code', 'INVALID_INPUT')),
      );
      expect(client.rpcLog, isEmpty);
    });

    test('rejects empty serviceId before RPC', () {
      expect(
        () => repo.updateService(
          serviceId: '   ',
          expectedUpdatedAt: expectedUpdatedAt,
          name: 'Updated',
          defaultPrice: '200.00',
          globalStatus: GlobalStatus.active,
        ),
        throwsA(isA<RpcFailure>().having((error) => error.code, 'code', 'INVALID_INPUT')),
      );
      expect(client.rpcLog, isEmpty);
    });

    test('throws StateError when response shape is malformed', () async {
      client = ServiceCatalogRpcTestClient(
        rpcResults: {
          'update_service': {'success': true, 'data': null},
        },
      );
      repo = ServiceCatalogRepository(client);

      await expectLater(
        repo.updateService(
          serviceId: _serviceId,
          expectedUpdatedAt: expectedUpdatedAt,
          name: 'Updated',
          defaultPrice: '200.00',
          globalStatus: GlobalStatus.active,
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('ServiceCatalogRepository setGlobalStatus', () {
    final expectedUpdatedAt = DateTime.utc(2026, 1, 2, 10);

    test('returns updated status on success', () async {
      final result = await repo.setGlobalStatus(
        serviceId: _serviceId,
        expectedUpdatedAt: expectedUpdatedAt,
        globalStatus: GlobalStatus.inactive,
      );

      expect(result.serviceId, _serviceId);
      expect(result.globalStatus, GlobalStatus.inactive);
      expect(result.updatedAt, DateTime.parse(_updatedAt));
      expect(client.lastFunction, 'set_service_global_status');
      expect(client.lastParams?['p_global_status'], 'inactive');
    });

    test('rejects empty serviceId before RPC', () {
      expect(
        () => repo.setGlobalStatus(
          serviceId: '   ',
          expectedUpdatedAt: expectedUpdatedAt,
          globalStatus: GlobalStatus.inactive,
        ),
        throwsA(isA<RpcFailure>().having((error) => error.code, 'code', 'INVALID_INPUT')),
      );
      expect(client.rpcLog, isEmpty);
    });

    test('throws StateError when response shape is malformed', () async {
      client = ServiceCatalogRpcTestClient(
        rpcResults: {
          'set_service_global_status': {
            'success': true,
            'data': {'service_id': _serviceId},
          },
        },
      );
      repo = ServiceCatalogRepository(client);

      await expectLater(
        repo.setGlobalStatus(
          serviceId: _serviceId,
          expectedUpdatedAt: expectedUpdatedAt,
          globalStatus: GlobalStatus.inactive,
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('ServiceCatalogRepository softDeleteService', () {
    final expectedUpdatedAt = DateTime.utc(2026, 1, 2, 10);

    test('returns deleted service id on success', () async {
      final deletedId = await repo.softDeleteService(
        serviceId: '  $_serviceId  ',
        expectedUpdatedAt: expectedUpdatedAt,
      );

      expect(deletedId, _serviceId);
      expect(client.lastFunction, 'soft_delete_service');
      expect(client.lastParams?['p_service_id'], _serviceId);
      expect(client.lastParams?['p_expected_updated_at'], expectedUpdatedAt.toUtc().toIso8601String());
    });

    test('rejects empty serviceId before RPC', () {
      expect(
        () => repo.softDeleteService(
          serviceId: '   ',
          expectedUpdatedAt: expectedUpdatedAt,
        ),
        throwsA(isA<RpcFailure>().having((error) => error.code, 'code', 'INVALID_INPUT')),
      );
      expect(client.rpcLog, isEmpty);
    });

    test('throws StateError when response shape is malformed', () async {
      client = ServiceCatalogRpcTestClient(
        rpcResults: {
          'soft_delete_service': {'success': true, 'data': {}},
        },
      );
      repo = ServiceCatalogRepository(client);

      await expectLater(
        repo.softDeleteService(
          serviceId: _serviceId,
          expectedUpdatedAt: expectedUpdatedAt,
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('ServiceCatalogRepository listServices', () {
    test('forwards pagination params', () async {
      final page = await repo.listServices(limit: 10, offset: 5);

      expect(client.lastFunction, 'list_services');
      expect(client.lastParams?['p_limit'], 10);
      expect(client.lastParams?['p_offset'], 5);
      expect(page.total, 2);
    });

    test('forwards optional filters when provided', () async {
      await repo.listServices(
        query: '  consult  ',
        globalStatus: GlobalStatus.active,
        branchId: '  $_branchId  ',
      );

      expect(client.lastParams?['p_query'], 'consult');
      expect(client.lastParams?['p_global_status'], 'active');
      expect(client.lastParams?['p_branch_id'], _branchId);
    });

    test('omits empty query and branchId', () async {
      await repo.listServices(query: '   ', branchId: '   ');

      expect(client.lastParams?.containsKey('p_query'), isFalse);
      expect(client.lastParams?.containsKey('p_branch_id'), isFalse);
    });

    test('skips invalid rows and parses valid items', () async {
      final page = await repo.listServices();

      expect(page.items, hasLength(2));
      expect(page.items.first.serviceId, _serviceId);
      expect(page.items.last.name, 'X-Ray');
    });

    test('handles Map items that are not Map<String, dynamic>', () async {
      final mapRow = Map<Object, Object>.from({
        'service_id': _serviceId,
        'name': 'Map Row',
        'default_price': '99.00',
        'global_status': 'active',
        'assigned_branch_count': 1,
        'updated_at': '2026-01-01T10:00:00.000Z',
      });
      client = ServiceCatalogRpcTestClient(
        rpcResults: {
          'list_services': {
            'success': true,
            'data': {
              'total': 1,
              'items': [mapRow],
            },
          },
        },
      );
      repo = ServiceCatalogRepository(client);

      final page = await repo.listServices();

      expect(page.items, hasLength(1));
      expect(page.items.first.name, 'Map Row');
    });
  });

  group('ServiceCatalogRepository copyConfiguration', () {
    test('returns copy result without serviceIds', () async {
      final result = await repo.copyConfiguration(
        sourceBranchId: '  $_branchId  ',
        targetBranchId: '  $_branchId2  ',
        mode: '  merge  ',
      );

      expect(result.affectedServiceIds, [_serviceId]);
      expect(result.createdCount, 1);
      expect(result.overwrittenCount, 0);
      expect(client.lastFunction, 'copy_service_branch_configuration');
      expect(client.lastParams?['p_source_branch_id'], _branchId);
      expect(client.lastParams?['p_target_branch_id'], _branchId2);
      expect(client.lastParams?['p_mode'], 'merge');
      expect(client.lastParams?.containsKey('p_service_ids'), isFalse);
    });

    test('forwards serviceIds when provided', () async {
      await repo.copyConfiguration(
        sourceBranchId: _branchId,
        targetBranchId: _branchId2,
        mode: 'overwrite',
        serviceIds: [_serviceId],
      );

      expect(client.lastParams?['p_service_ids'], [_serviceId]);
    });

    test('rejects empty sourceBranchId before RPC', () {
      expect(
        () => repo.copyConfiguration(
          sourceBranchId: '   ',
          targetBranchId: _branchId2,
          mode: 'merge',
        ),
        throwsA(isA<RpcFailure>().having((error) => error.code, 'code', 'INVALID_INPUT')),
      );
      expect(client.rpcLog, isEmpty);
    });

    test('throws StateError when data is not a map', () async {
      client = ServiceCatalogRpcTestClient(
        rpcResults: {
          'copy_service_branch_configuration': {'success': true, 'data': null},
        },
      );
      repo = ServiceCatalogRepository(client);

      await expectLater(
        repo.copyConfiguration(
          sourceBranchId: _branchId,
          targetBranchId: _branchId2,
          mode: 'merge',
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('ServiceCatalogRepository setupNewBranchServices', () {
    test('returns target branch and assigned service ids on success', () async {
      final result = await repo.setupNewBranchServices(
        targetBranchId: '  $_branchId2  ',
        method: '  copy_from_branch  ',
        serviceIds: [_serviceId],
        sourceBranchId: '  $_branchId  ',
        mode: '  overwrite  ',
      );

      expect(result.targetBranchId, _branchId2);
      expect(result.assignedServiceIds, [_serviceId]);
      expect(client.lastFunction, 'setup_new_branch_services');
      expect(client.lastParams?['p_target_branch_id'], _branchId2);
      expect(client.lastParams?['p_method'], 'copy_from_branch');
      expect(client.lastParams?['p_mode'], 'overwrite');
      expect(client.lastParams?['p_service_ids'], [_serviceId]);
      expect(client.lastParams?['p_source_branch_id'], _branchId);
    });

    test('omits empty sourceBranchId and serviceIds', () async {
      await repo.setupNewBranchServices(
        targetBranchId: _branchId2,
        method: 'manual',
        sourceBranchId: '   ',
      );

      expect(client.lastParams?.containsKey('p_source_branch_id'), isFalse);
      expect(client.lastParams?.containsKey('p_service_ids'), isFalse);
    });

    test('rejects empty targetBranchId before RPC', () {
      expect(
        () => repo.setupNewBranchServices(
          targetBranchId: '   ',
          method: 'manual',
        ),
        throwsA(isA<RpcFailure>().having((error) => error.code, 'code', 'INVALID_INPUT')),
      );
      expect(client.rpcLog, isEmpty);
    });

    test('throws StateError when target_branch_id is missing', () async {
      client = ServiceCatalogRpcTestClient(
        rpcResults: {
          'setup_new_branch_services': {'success': true, 'data': {}},
        },
      );
      repo = ServiceCatalogRepository(client);

      await expectLater(
        repo.setupNewBranchServices(
          targetBranchId: _branchId2,
          method: 'manual',
        ),
        throwsA(isA<StateError>()),
      );
    });
  });
}
