import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/billing/data/invoice_repository.dart';
import 'package:ai_clinic/features/billing/domain/discount_kind.dart';
import 'package:ai_clinic/features/billing/domain/discount_scope.dart';
import 'package:ai_clinic/features/billing/domain/invoice_detail.dart';
import 'package:ai_clinic/features/billing/domain/invoice_item.dart';
import 'package:ai_clinic/features/billing/domain/invoice_status.dart';
import 'package:ai_clinic/features/billing/domain/money.dart';
import 'package:ai_clinic/features/billing/presentation/providers/invoice_editor_notifier.dart';
import 'package:ai_clinic/features/service_catalog/data/service_catalog_repository.dart';
import 'package:ai_clinic/features/service_catalog/domain/effective_price.dart';
import 'package:ai_clinic/features/service_catalog/domain/eligible_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../support/billing_rpc_test_client.dart';
import '../../support/fake_postgrest_rpc.dart';

void main() {
  const invoiceId = BillingRpcTestClient.draftInvoiceId;

  group('InvoiceEditorNotifier', () {
    late BillingRpcTestClient billingClient;
    late _TrackingCatalogClient catalogClient;

    setUp(() {
      billingClient = BillingRpcTestClient();
      catalogClient = _TrackingCatalogClient();
    });

    ProviderContainer createContainer() {
      return ProviderContainer(
        overrides: [
          invoiceRepositoryProvider.overrideWithValue(InvoiceRepository(billingClient)),
          serviceCatalogRepositoryProvider.overrideWithValue(ServiceCatalogRepository(catalogClient)),
        ],
      );
    }

    test('build loads invoice detail on success', () async {
      final container = createContainer();
      addTearDown(container.dispose);

      final state = await container.read(invoiceEditorProvider(invoiceId).future);

      expect(state.invoice.id, invoiceId);
      expect(state.invoice.status, InvoiceStatus.draft);
      expect(billingClient.rpcLog, contains('get_invoice_detail'));
    });

    test('build surfaces repository errors as AsyncError', () async {
      billingClient.rpcResults['get_invoice_detail'] = {
        'success': false,
        'error_code': 'NOT_FOUND',
        'error_message': 'Invoice not found.',
      };
      final container = createContainer();
      addTearDown(container.dispose);

      final provider = invoiceEditorProvider(invoiceId);
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(subscription.close);

      container.read(provider);
      await pumpEventQueue();

      final asyncValue = container.read(provider);
      expect(asyncValue.hasError, isTrue);
      expect(asyncValue.error, isA<RpcFailure>().having((error) => error.code, 'code', 'NOT_FOUND'));
    });

    test('reload refreshes invoice detail on success', () async {
      final container = createContainer();
      addTearDown(container.dispose);

      await container.read(invoiceEditorProvider(invoiceId).future);
      billingClient.rpcLog.clear();

      await container.read(invoiceEditorProvider(invoiceId).notifier).reload();

      expect(billingClient.rpcLog, ['get_invoice_detail']);
      expect(container.read(invoiceEditorProvider(invoiceId)).value?.invoice.id, invoiceId);
    });

    test('reload surfaces repository errors', () async {
      final container = createContainer();
      addTearDown(container.dispose);

      await container.read(invoiceEditorProvider(invoiceId).future);
      billingClient.rpcResults['get_invoice_detail'] = {
        'success': false,
        'error_code': 'RPC_ERROR',
        'error_message': 'Reload failed.',
      };

      await container.read(invoiceEditorProvider(invoiceId).notifier).reload();

      final state = container.read(invoiceEditorProvider(invoiceId));
      expect(state.hasError, isTrue);
      expect(state.error, isA<RpcFailure>());
    });

    test('mutations set isMutating during the call and clear it after refresh', () async {
      final container = createContainer();
      addTearDown(container.dispose);

      final notifier = container.read(invoiceEditorProvider(invoiceId).notifier);
      await container.read(invoiceEditorProvider(invoiceId).future);

      final mutation = notifier.addItem(description: 'Consultation', quantity: '1', unitPrice: '100.00');
      expect(container.read(invoiceEditorProvider(invoiceId)).value?.isMutating, isTrue);

      await mutation;

      final state = container.read(invoiceEditorProvider(invoiceId)).value;
      expect(state?.isMutating, isFalse);
      expect(state?.invoice.items, isNotEmpty);
      expect(billingClient.rpcLog.where((fn) => fn == 'get_invoice_detail').length, greaterThanOrEqualTo(2));
    });

    test('STALE_INVOICE rolls back state and throws InvoiceStaleException', () async {
      final container = createContainer();
      addTearDown(container.dispose);

      final provider = invoiceEditorProvider(invoiceId);
      final notifier = container.read(provider.notifier);
      await container.read(provider.future);
      final before = container.read(provider).value!;

      billingClient.rpcResults['add_invoice_item'] = {
        'success': false,
        'error_code': 'STALE_INVOICE',
        'error_message': 'Invoice was updated elsewhere.',
      };

      await expectLater(
        notifier.addItem(description: 'Late fee', quantity: '1', unitPrice: '25.00'),
        throwsA(isA<InvoiceStaleException>()),
      );

      final after = container.read(provider).value!;
      expect(after.invoice.updatedAt, before.invoice.updatedAt);
      expect(after.isMutating, isFalse);
    });

    test('other RpcFailure rolls back state and rethrows', () async {
      final container = createContainer();
      addTearDown(container.dispose);

      final provider = invoiceEditorProvider(invoiceId);
      final notifier = container.read(provider.notifier);
      await container.read(provider.future);
      final before = container.read(provider).value!;

      billingClient.rpcResults['add_invoice_item'] = {
        'success': false,
        'error_code': 'INVALID_INPUT',
        'error_message': 'Description is required.',
      };

      await expectLater(
        notifier.addItem(description: 'Late fee', quantity: '1', unitPrice: '25.00'),
        throwsA(isA<RpcFailure>().having((error) => error.code, 'code', 'INVALID_INPUT')),
      );

      expect(container.read(provider).value?.invoice.updatedAt, before.invoice.updatedAt);
      expect(container.read(provider).value?.isMutating, isFalse);
    });

    test('non-RPC errors roll back state and rethrow', () async {
      final explodingCatalog = _ExplodingCatalogClient();
      final container = ProviderContainer(
        overrides: [
          invoiceRepositoryProvider.overrideWithValue(InvoiceRepository(billingClient)),
          serviceCatalogRepositoryProvider.overrideWithValue(ServiceCatalogRepository(explodingCatalog)),
        ],
      );
      addTearDown(container.dispose);

      final provider = invoiceEditorProvider(invoiceId);
      final notifier = container.read(provider.notifier);
      await container.read(provider.future);
      final before = container.read(provider).value!;

      await expectLater(notifier.addItemFromService(_sampleEligibleService()), throwsA(isA<Exception>()));

      expect(container.read(provider).value?.invoice.updatedAt, before.invoice.updatedAt);
      expect(container.read(provider).value?.isMutating, isFalse);
    });

    test('mutation before invoice loads throws StateError', () async {
      final container = createContainer();
      addTearDown(container.dispose);

      final notifier = container.read(invoiceEditorProvider(invoiceId).notifier);

      await expectLater(
        notifier.addItem(description: 'Too early', quantity: '1', unitPrice: '10.00'),
        throwsA(isA<StateError>().having((error) => error.message, 'message', 'Invoice not loaded.')),
      );
    });

    test('updateItemQuantity with unknown itemId throws', () async {
      final container = createContainer();
      addTearDown(container.dispose);

      final notifier = container.read(invoiceEditorProvider(invoiceId).notifier);
      await container.read(invoiceEditorProvider(invoiceId).future);

      await expectLater(notifier.updateItemQuantity(itemId: 'missing-item', quantity: '2'), throwsA(isA<StateError>()));
    });

    test('addItemFromService uses the service catalog repository', () async {
      final container = createContainer();
      addTearDown(container.dispose);

      final provider = invoiceEditorProvider(invoiceId);
      final notifier = container.read(provider.notifier);
      await container.read(provider.future);
      final expectedUpdatedAt = container.read(provider).value!.invoice.updatedAt;

      final itemId = await notifier.addItemFromService(_sampleEligibleService());

      expect(itemId, 'svc-item-1');
      expect(catalogClient.calls, ['add_invoice_item_from_service']);
      expect(billingClient.rpcLog, isNot(contains('add_invoice_item_from_service')));
      expect(
        catalogClient.paramsForFunction('add_invoice_item_from_service')?['p_expected_updated_at'],
        expectedUpdatedAt.toUtc().toIso8601String(),
      );
    });

    test('each public mutation passes expectedUpdatedAt from the loaded invoice', () async {
      final container = createContainer();
      addTearDown(container.dispose);

      final provider = invoiceEditorProvider(invoiceId);
      final notifier = container.read(provider.notifier);
      await container.read(provider.future);

      void expectRpcExpectedUpdatedAt(String rpcName, DateTime expectedUpdatedAt) {
        expect(
          billingClient.paramsForFunction(rpcName)?['p_expected_updated_at'] ??
              catalogClient.paramsForFunction(rpcName)?['p_expected_updated_at'],
          expectedUpdatedAt.toUtc().toIso8601String(),
        );
      }

      var expectedUpdatedAt = container.read(provider).value!.invoice.updatedAt;
      await notifier.addItem(description: 'Manual item', quantity: '1', unitPrice: '40.00');
      expectRpcExpectedUpdatedAt('add_invoice_item', expectedUpdatedAt);

      expectedUpdatedAt = container.read(provider).value!.invoice.updatedAt;
      await notifier.addItemFromService(_sampleEligibleService());
      expectRpcExpectedUpdatedAt('add_invoice_item_from_service', expectedUpdatedAt);

      final itemId = container.read(provider).value!.invoice.items.first.id;

      expectedUpdatedAt = container.read(provider).value!.invoice.updatedAt;
      await notifier.updateItemQuantity(itemId: itemId, quantity: '2');
      expectRpcExpectedUpdatedAt('update_invoice_item', expectedUpdatedAt);

      expectedUpdatedAt = container.read(provider).value!.invoice.updatedAt;
      await notifier.updateItem(itemId: itemId, description: 'Updated item', quantity: '2', unitPrice: '45.00');
      expectRpcExpectedUpdatedAt('update_invoice_item', expectedUpdatedAt);

      expectedUpdatedAt = container.read(provider).value!.invoice.updatedAt;
      await notifier.applyInvoiceDiscount(kind: DiscountKind.percentage, value: '10');
      expectRpcExpectedUpdatedAt('apply_invoice_discount', expectedUpdatedAt);

      expectedUpdatedAt = container.read(provider).value!.invoice.updatedAt;
      await notifier.setInsuranceCoverage(providerId: BillingRpcTestClient.insuranceProviderId, coveredAmount: '5.00');
      expectRpcExpectedUpdatedAt('set_insurance_coverage', expectedUpdatedAt);

      final removableItemId = container.read(provider).value!.invoice.items.last.id;
      expectedUpdatedAt = container.read(provider).value!.invoice.updatedAt;
      await notifier.removeItem(removableItemId);
      expectRpcExpectedUpdatedAt('remove_invoice_item', expectedUpdatedAt);
    });

    test('applyLineDiscount, issue, and discardDraft mutations', () async {
      final discountClient = BillingRpcTestClient();
      final discountCatalog = _TrackingCatalogClient();
      final discountContainer = ProviderContainer(
        overrides: [
          invoiceRepositoryProvider.overrideWithValue(InvoiceRepository(discountClient)),
          serviceCatalogRepositoryProvider.overrideWithValue(ServiceCatalogRepository(discountCatalog)),
        ],
      );
      addTearDown(discountContainer.dispose);

      final discountProvider = invoiceEditorProvider(invoiceId);
      final discountNotifier = discountContainer.read(discountProvider.notifier);
      await discountContainer.read(discountProvider.future);

      await discountNotifier.addItem(description: 'Discount target', quantity: '1', unitPrice: '80.00');
      final itemId = discountContainer.read(discountProvider).value!.invoice.items.single.id;
      final expectedUpdatedAt = discountContainer.read(discountProvider).value!.invoice.updatedAt;

      await discountNotifier.applyLineDiscount(itemId: itemId, kind: DiscountKind.fixed, value: '10');
      expect(
        discountClient.paramsForFunction('apply_line_discount')?['p_expected_updated_at'],
        expectedUpdatedAt.toUtc().toIso8601String(),
      );

      final issueClient = BillingRpcTestClient();
      final issueCatalog = _TrackingCatalogClient();
      final issueContainer = ProviderContainer(
        overrides: [
          invoiceRepositoryProvider.overrideWithValue(InvoiceRepository(issueClient)),
          serviceCatalogRepositoryProvider.overrideWithValue(ServiceCatalogRepository(issueCatalog)),
        ],
      );
      addTearDown(issueContainer.dispose);
      final issueProvider = invoiceEditorProvider(invoiceId);
      final issueNotifier = issueContainer.read(issueProvider.notifier);
      await issueContainer.read(issueProvider.future);
      await issueNotifier.addItem(description: 'Billable', quantity: '1', unitPrice: '50.00');
      final issueUpdatedAt = issueContainer.read(issueProvider).value!.invoice.updatedAt;

      final invoiceNumber = await issueNotifier.issue();
      expect(invoiceNumber, 'INV-MAIN-000001');
      expect(
        issueClient.paramsForFunction('issue_invoice')?['p_expected_updated_at'],
        issueUpdatedAt.toUtc().toIso8601String(),
      );

      final discardClient = BillingRpcTestClient();
      final discardCatalog = _TrackingCatalogClient();
      final discardContainer = ProviderContainer(
        overrides: [
          invoiceRepositoryProvider.overrideWithValue(InvoiceRepository(discardClient)),
          serviceCatalogRepositoryProvider.overrideWithValue(ServiceCatalogRepository(discardCatalog)),
        ],
      );
      addTearDown(discardContainer.dispose);
      final discardProvider = invoiceEditorProvider(invoiceId);
      final discardNotifier = discardContainer.read(discardProvider.notifier);
      await discardContainer.read(discardProvider.future);
      final discardUpdatedAt = discardContainer.read(discardProvider).value!.invoice.updatedAt;

      await discardNotifier.discardDraft();
      expect(
        discardClient.paramsForFunction('discard_draft_invoice')?['p_expected_updated_at'],
        discardUpdatedAt.toUtc().toIso8601String(),
      );
      expect(discardClient.rpcLog, contains('discard_draft_invoice'));
    });
  });

  group('InvoiceEditorState', () {
    test('computed discount getters prefer line scope over invoice scope', () {
      final invoice = _minimalInvoiceDetail(
        discountAmount: Money.parse('15.00'),
        items: [
          InvoiceItem(
            id: 'line-1',
            description: 'Service',
            quantity: '1',
            unitPrice: Money.parse('100.00'),
            lineSubtotal: Money.parse('100.00'),
            lineDiscountAmount: Money.parse('5.00'),
            lineTotal: Money.parse('95.00'),
          ),
        ],
      );

      final withLine = InvoiceEditorState(invoice: invoice);
      expect(withLine.hasLineDiscounts, isTrue);
      expect(withLine.hasInvoiceDiscount, isTrue);
      expect(withLine.activeDiscountScope, DiscountScope.line);

      final invoiceOnly = _minimalInvoiceDetail(discountAmount: Money.parse('10.00'));
      final invoiceScope = InvoiceEditorState(invoice: invoiceOnly);
      expect(invoiceScope.hasLineDiscounts, isFalse);
      expect(invoiceScope.hasInvoiceDiscount, isTrue);
      expect(invoiceScope.activeDiscountScope, DiscountScope.invoice);

      final noDiscounts = _minimalInvoiceDetail();
      final none = InvoiceEditorState(invoice: noDiscounts);
      expect(none.hasLineDiscounts, isFalse);
      expect(none.hasInvoiceDiscount, isFalse);
      expect(none.activeDiscountScope, isNull);
    });

    test('copyWith replaces invoice and isMutating when provided', () {
      final invoice = _minimalInvoiceDetail();
      final other = _minimalInvoiceDetail(discountAmount: Money.parse('1.00'));

      final original = InvoiceEditorState(invoice: invoice, isMutating: false);
      final copied = original.copyWith(invoice: other, isMutating: true);

      expect(copied.invoice.discountAmount, Money.parse('1.00'));
      expect(copied.isMutating, isTrue);
      expect(original.isMutating, isFalse);
    });
  });
}

EligibleService _sampleEligibleService() {
  return EligibleService(
    serviceId: 'service-catalog-1',
    name: 'Consultation',
    unitPrice: Money.parse('75.00'),
    appliedRule: AppliedPriceRule.defaultPrice,
    onPromotion: false,
  );
}

InvoiceDetail _minimalInvoiceDetail({Money? discountAmount, List<InvoiceItem> items = const []}) {
  final resolvedDiscountAmount = discountAmount ?? Money.zero;
  final timestamp = DateTime.utc(2026, 6, 1, 10);
  return InvoiceDetail(
    id: BillingRpcTestClient.draftInvoiceId,
    status: InvoiceStatus.draft,
    branchId: '44444444-4444-4444-8444-444444444444',
    patientId: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
    visitId: BillingRpcTestClient.visitId,
    subtotal: Money.zero,
    discountAmount: resolvedDiscountAmount,
    insuranceCoveredAmount: Money.zero,
    currency: 'USD',
    balance: Money.zero,
    createdAt: timestamp,
    updatedAt: timestamp,
    items: items,
    payments: const [],
  );
}

class _TrackingCatalogClient extends BillingRpcTestClient {
  final List<String> calls = <String>[];

  @override
  Map<String, dynamic>? paramsForFunction(String fn) {
    for (var i = rpcCalls.length - 1; i >= 0; i--) {
      if (rpcCalls[i].fn == fn) {
        return rpcCalls[i].params;
      }
    }
    return null;
  }

  @override
  PostgrestFilterBuilder<T> rpc<T>(String fn, {Map<String, dynamic>? params, dynamic get = false}) {
    calls.add(fn);
    final copied = params == null ? null : Map<String, dynamic>.from(params);
    rpcCalls.add((fn: fn, params: copied));
    lastFunction = fn;
    lastParams = copied;
    return FakePostgrestRpc({
          'success': true,
          'data': {'item_id': 'svc-item-1', 'quantity': '1', 'unit_price': '75.00', 'applied_rule': 'default'},
        })
        as PostgrestFilterBuilder<T>;
  }
}

class _ExplodingCatalogClient extends RpcCaptureSupabaseClient {
  @override
  PostgrestFilterBuilder<T> rpc<T>(String fn, {Map<String, dynamic>? params, dynamic get = false}) {
    throw Exception('catalog unavailable');
  }
}
