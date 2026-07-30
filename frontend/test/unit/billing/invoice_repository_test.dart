import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/billing/data/invoice_repository.dart';
import 'package:ai_clinic/features/billing/domain/discount_kind.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/billing_rpc_test_client.dart';

void main() {
  late BillingRpcTestClient client;
  late InvoiceRepository repo;

  setUp(() {
    client = BillingRpcTestClient();
    repo = InvoiceRepository(client);
  });

  group('InvoiceRepository list pagination', () {
    test('listInvoices exposes backend has_more flag', () async {
      final page = await repo.listInvoices(limit: 1, offset: 0);

      expect(page.items, hasLength(1));
      expect(page.hasMore, isTrue);
    });
  });

  group('InvoiceRepository validation', () {
    test('addItem rejects description longer than 500 characters', () {
      final longDescription = 'x' * 501;

      expect(
        () => repo.addItem(
          invoiceId: BillingRpcTestClient.draftInvoiceId,
          expectedUpdatedAt: DateTime.utc(2026, 6, 1),
          description: longDescription,
          quantity: '1',
          unitPrice: '10',
        ),
        throwsA(
          isA<RpcFailure>().having((error) => error.message, 'message', 'Description must be 500 characters or fewer.'),
        ),
      );
      expect(client.rpcLog, isEmpty);
    });

    test('setInsuranceCoverage uses field-specific negative amount message', () {
      expect(
        () => repo.setInsuranceCoverage(
          invoiceId: BillingRpcTestClient.draftInvoiceId,
          expectedUpdatedAt: DateTime.utc(2026, 6, 1),
          coveredAmount: '-1',
        ),
        throwsA(isA<RpcFailure>().having((error) => error.message, 'message', 'coveredAmount cannot be negative.')),
      );
    });
  });

  group('findForVisit', () {
    test('excludes voided invoices via statuses filter', () async {
      final item = await repo.findForVisit(visitId: BillingRpcTestClient.visitId);

      expect(item, isNotNull);
      expect(item!.id, BillingRpcTestClient.draftInvoiceId);
      expect(item.status.name, 'draft');

      final lastCall = client.lastParams;
      final filters = lastCall?['p_filters'] as Map?;
      expect(filters?['visit_id'], BillingRpcTestClient.visitId);
      expect(filters?['statuses'], ['draft', 'issued', 'partially_paid', 'paid']);
    });
  });

  group('InvoiceRepository createFromVisit', () {
    test('returns invoice id on success', () async {
      final invoiceId = await repo.createFromVisit(visitId: BillingRpcTestClient.visitId);

      expect(invoiceId, BillingRpcTestClient.draftInvoiceId);
      expect(client.lastFunction, 'create_invoice_from_visit');
      expect(client.lastParams?['p_visit_id'], BillingRpcTestClient.visitId);
    });

    test('rejects empty visitId before RPC', () {
      expect(
        () => repo.createFromVisit(visitId: '   '),
        throwsA(isA<RpcFailure>().having((error) => error.code, 'code', 'INVALID_INPUT')),
      );
      expect(client.rpcLog, isEmpty);
    });

    test('throws StateError when invoice_id is missing', () async {
      client = BillingRpcTestClient(
        rpcResults: {
          'create_invoice_from_visit': {'success': true, 'data': null},
        },
      );
      repo = InvoiceRepository(client);

      expect(
        () => repo.createFromVisit(visitId: BillingRpcTestClient.visitId),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('InvoiceRepository discardDraft', () {
    test('sends trimmed invoice id and UTC expected timestamp', () async {
      final localUpdatedAt = DateTime(2026, 6, 1, 14, 30);

      await repo.discardDraft(
        invoiceId: '  ${BillingRpcTestClient.draftInvoiceId}  ',
        expectedUpdatedAt: localUpdatedAt,
      );

      expect(client.lastFunction, 'discard_draft_invoice');
      expect(client.lastParams?['p_invoice_id'], BillingRpcTestClient.draftInvoiceId);
      expect(client.lastParams?['p_expected_updated_at'], localUpdatedAt.toUtc().toIso8601String());
    });
  });

  group('InvoiceRepository addItem', () {
    final expectedUpdatedAt = DateTime.utc(2026, 6, 1, 10);

    test('returns item id on success', () async {
      final itemId = await repo.addItem(
        invoiceId: BillingRpcTestClient.draftInvoiceId,
        expectedUpdatedAt: expectedUpdatedAt,
        description: 'Consultation',
        quantity: '1',
        unitPrice: '100',
      );

      expect(itemId, BillingRpcTestClient.itemId);
      expect(client.lastFunction, 'add_invoice_item');
      expect(client.lastParams?['p_description'], 'Consultation');
      expect(client.lastParams?['p_quantity'], '1');
      expect(client.lastParams?['p_unit_price'], '100');
      expect(client.lastParams?['p_expected_updated_at'], expectedUpdatedAt.toUtc().toIso8601String());
    });

    test('rejects zero quantity before RPC', () {
      expect(
        () => repo.addItem(
          invoiceId: BillingRpcTestClient.draftInvoiceId,
          expectedUpdatedAt: expectedUpdatedAt,
          description: 'Item',
          quantity: '0',
          unitPrice: '10',
        ),
        throwsA(
          isA<RpcFailure>().having(
            (error) => error.message,
            'message',
            'Quantity must be greater than zero.',
          ),
        ),
      );
      expect(client.rpcLog, isEmpty);
    });

    test('rejects negative quantity before RPC', () {
      expect(
        () => repo.addItem(
          invoiceId: BillingRpcTestClient.draftInvoiceId,
          expectedUpdatedAt: expectedUpdatedAt,
          description: 'Item',
          quantity: '-1',
          unitPrice: '10',
        ),
        throwsA(
          isA<RpcFailure>().having(
            (error) => error.message,
            'message',
            'Quantity must be greater than zero.',
          ),
        ),
      );
      expect(client.rpcLog, isEmpty);
    });

    test('rejects non-numeric quantity before RPC', () {
      expect(
        () => repo.addItem(
          invoiceId: BillingRpcTestClient.draftInvoiceId,
          expectedUpdatedAt: expectedUpdatedAt,
          description: 'Item',
          quantity: 'abc',
          unitPrice: '10',
        ),
        throwsA(
          isA<RpcFailure>().having(
            (error) => error.message,
            'message',
            'Quantity must be greater than zero.',
          ),
        ),
      );
      expect(client.rpcLog, isEmpty);
    });

    test('rejects negative unitPrice before RPC', () {
      expect(
        () => repo.addItem(
          invoiceId: BillingRpcTestClient.draftInvoiceId,
          expectedUpdatedAt: expectedUpdatedAt,
          description: 'Item',
          quantity: '1',
          unitPrice: '-5',
        ),
        throwsA(isA<RpcFailure>().having((error) => error.message, 'message', 'unitPrice cannot be negative.')),
      );
      expect(client.rpcLog, isEmpty);
    });
  });

  group('InvoiceRepository updateItem', () {
    test('forwards trimmed params and UTC expected timestamp', () async {
      final localUpdatedAt = DateTime(2026, 6, 2, 9, 15);

      await repo.updateItem(
        itemId: '  ${BillingRpcTestClient.itemId}  ',
        expectedUpdatedAt: localUpdatedAt,
        description: '  Updated item  ',
        quantity: '2',
        unitPrice: '50',
      );

      expect(client.lastFunction, 'update_invoice_item');
      expect(client.lastParams?['p_item_id'], BillingRpcTestClient.itemId);
      expect(client.lastParams?['p_description'], 'Updated item');
      expect(client.lastParams?['p_quantity'], '2');
      expect(client.lastParams?['p_unit_price'], '50');
      expect(client.lastParams?['p_expected_updated_at'], localUpdatedAt.toUtc().toIso8601String());
    });
  });

  group('InvoiceRepository removeItem', () {
    test('forwards trimmed item id and UTC expected timestamp', () async {
      final localUpdatedAt = DateTime(2026, 6, 2, 12, 0);

      await repo.removeItem(
        itemId: '  ${BillingRpcTestClient.itemId}  ',
        expectedUpdatedAt: localUpdatedAt,
      );

      expect(client.lastFunction, 'remove_invoice_item');
      expect(client.lastParams?['p_item_id'], BillingRpcTestClient.itemId);
      expect(client.lastParams?['p_expected_updated_at'], localUpdatedAt.toUtc().toIso8601String());
    });
  });

  group('InvoiceRepository issue', () {
    test('returns invoice number on success', () async {
      final invoiceNumber = await repo.issue(
        invoiceId: BillingRpcTestClient.draftInvoiceId,
        expectedUpdatedAt: DateTime.utc(2026, 6, 1, 10),
      );

      expect(invoiceNumber, 'INV-MAIN-000001');
      expect(client.lastFunction, 'issue_invoice');
    });

    test('throws StateError when invoice_number is missing', () async {
      client = BillingRpcTestClient(
        rpcResults: {
          'issue_invoice': {'success': true, 'data': null},
        },
      );
      repo = InvoiceRepository(client);

      expect(
        () => repo.issue(
          invoiceId: BillingRpcTestClient.draftInvoiceId,
          expectedUpdatedAt: DateTime.utc(2026, 6, 1, 10),
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('InvoiceRepository discounts', () {
    final expectedUpdatedAt = DateTime.utc(2026, 6, 1, 10);

    setUp(() async {
      await repo.addItem(
        invoiceId: BillingRpcTestClient.draftInvoiceId,
        expectedUpdatedAt: expectedUpdatedAt,
        description: 'Consultation',
        quantity: '1',
        unitPrice: '100',
      );
    });

    test('applyLineDiscount sends discount kind wire value', () async {
      await repo.applyLineDiscount(
        itemId: BillingRpcTestClient.itemId,
        expectedUpdatedAt: expectedUpdatedAt,
        kind: DiscountKind.percentage,
        value: '10',
      );

      expect(client.lastFunction, 'apply_line_discount');
      expect(client.lastParams?['p_kind'], 'percentage');
      expect(client.lastParams?['p_value'], '10');
    });

    test('applyLineDiscount sends null kind when clearing', () async {
      await repo.applyLineDiscount(
        itemId: BillingRpcTestClient.itemId,
        expectedUpdatedAt: expectedUpdatedAt,
      );

      expect(client.lastParams?['p_kind'], isNull);
      expect(client.lastParams?['p_value'], isNull);
    });

    test('applyInvoiceDiscount sends discount kind wire value', () async {
      await repo.applyInvoiceDiscount(
        invoiceId: BillingRpcTestClient.draftInvoiceId,
        expectedUpdatedAt: expectedUpdatedAt,
        kind: DiscountKind.fixed,
        value: '15',
      );

      expect(client.lastFunction, 'apply_invoice_discount');
      expect(client.lastParams?['p_kind'], 'fixed');
      expect(client.lastParams?['p_value'], '15');
    });

    test('applyInvoiceDiscount sends null kind when clearing', () async {
      await repo.applyInvoiceDiscount(
        invoiceId: BillingRpcTestClient.draftInvoiceId,
        expectedUpdatedAt: expectedUpdatedAt,
      );

      expect(client.lastParams?['p_kind'], isNull);
      expect(client.lastParams?['p_value'], isNull);
    });
  });

  group('InvoiceRepository setInsuranceCoverage', () {
    final expectedUpdatedAt = DateTime.utc(2026, 6, 1, 10);

    setUp(() async {
      await repo.addItem(
        invoiceId: BillingRpcTestClient.draftInvoiceId,
        expectedUpdatedAt: expectedUpdatedAt,
        description: 'Consultation',
        quantity: '1',
        unitPrice: '100',
      );
    });

    test('forwards provider and covered amount on success', () async {
      await repo.setInsuranceCoverage(
        invoiceId: BillingRpcTestClient.draftInvoiceId,
        expectedUpdatedAt: expectedUpdatedAt,
        providerId: BillingRpcTestClient.insuranceProviderId,
        coveredAmount: '25.00',
      );

      expect(client.lastFunction, 'set_insurance_coverage');
      expect(client.lastParams?['p_provider_id'], BillingRpcTestClient.insuranceProviderId);
      expect(client.lastParams?['p_covered_amount'], '25.00');
    });
  });

  group('InvoiceRepository voidInvoice', () {
    test('forwards trimmed reason and UTC expected timestamp', () async {
      client.issuedUpdatedAt = DateTime.utc(2026, 6, 2, 11, 0);
      final localUpdatedAt = DateTime(2026, 6, 2, 14, 0);

      await repo.voidInvoice(
        invoiceId: BillingRpcTestClient.issuedInvoiceId,
        expectedUpdatedAt: localUpdatedAt,
        reason: '  Duplicate charge  ',
      );

      expect(client.lastFunction, 'void_invoice');
      expect(client.lastParams?['p_invoice_id'], BillingRpcTestClient.issuedInvoiceId);
      expect(client.lastParams?['p_reason'], 'Duplicate charge');
      expect(client.lastParams?['p_expected_updated_at'], localUpdatedAt.toUtc().toIso8601String());
    });

    test('rejects empty reason before RPC', () {
      expect(
        () => repo.voidInvoice(
          invoiceId: BillingRpcTestClient.issuedInvoiceId,
          expectedUpdatedAt: DateTime.utc(2026, 6, 2, 11, 0),
          reason: '   ',
        ),
        throwsA(isA<RpcFailure>().having((error) => error.code, 'code', 'INVALID_INPUT')),
      );
      expect(client.rpcLog, isEmpty);
    });

    test('propagates STALE_INVOICE from server', () async {
      client = BillingRpcTestClient(
        rpcResults: {
          'void_invoice': {
            'success': false,
            'error_code': 'STALE_INVOICE',
            'error_message': 'Stale invoice.',
          },
        },
      );
      repo = InvoiceRepository(client);

      expect(
        () => repo.voidInvoice(
          invoiceId: BillingRpcTestClient.issuedInvoiceId,
          expectedUpdatedAt: DateTime.utc(2026, 6, 2, 11, 0),
          reason: 'Duplicate charge',
        ),
        throwsA(isA<RpcFailure>().having((error) => error.code, 'code', 'STALE_INVOICE')),
      );
    });
  });

  group('InvoiceRepository getDetail', () {
    test('returns parsed invoice detail on success', () async {
      final detail = await repo.getDetail(invoiceId: BillingRpcTestClient.issuedInvoiceId);

      expect(detail.id, BillingRpcTestClient.issuedInvoiceId);
      expect(detail.invoiceNumber, 'INV-MAIN-000001');
      expect(client.lastFunction, 'get_invoice_detail');
    });

    test('throws StateError when response shape is unparseable', () async {
      client = BillingRpcTestClient(
        rpcResults: {
          'get_invoice_detail': {'success': true, 'data': {}},
        },
      );
      repo = InvoiceRepository(client);

      expect(
        () => repo.getDetail(invoiceId: BillingRpcTestClient.issuedInvoiceId),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('InvoiceRepository listInvoices', () {
    test('forwards filters, limit, and offset', () async {
      final filters = {
        'statuses': ['issued'],
        'branch_ids': ['44444444-4444-4444-8444-444444444444'],
      };

      await repo.listInvoices(filters: filters, limit: 10, offset: 5);

      expect(client.lastFunction, 'list_invoices');
      expect(client.lastParams?['p_filters'], filters);
      expect(client.lastParams?['p_limit'], 10);
      expect(client.lastParams?['p_offset'], 5);
    });

    test('parses rows key when items is absent', () async {
      client = BillingRpcTestClient(
        rpcResults: {
          'list_invoices': {
            'success': true,
            'data': {
              'rows': [
                {
                  'id': BillingRpcTestClient.issuedInvoiceId,
                  'invoice_number': 'INV-MAIN-000001',
                  'status': 'issued',
                  'subtotal': '100',
                  'discount_amount': '0',
                  'insurance_covered_amount': '0',
                  'paid_amount': '0',
                  'balance': '100.00',
                  'currency': 'USD',
                  'created_at': '2026-06-02T10:00:00.000Z',
                },
                {'status': 'issued'},
              ],
              'has_more': false,
            },
          },
        },
      );
      repo = InvoiceRepository(client);

      final page = await repo.listInvoices();

      expect(page.items, hasLength(1));
      expect(page.items.first.id, BillingRpcTestClient.issuedInvoiceId);
      expect(page.hasMore, isFalse);
    });
  });

  group('InvoiceRepository listPatientInvoices', () {
    test('forwards patient id, limit, and offset', () async {
      const patientId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';

      final page = await repo.listPatientInvoices(patientId: '  $patientId  ', limit: 2, offset: 1);

      expect(client.lastFunction, 'list_patient_invoices');
      expect(client.lastParams?['p_patient_id'], patientId);
      expect(client.lastParams?['p_limit'], 2);
      expect(client.lastParams?['p_offset'], 1);
      expect(page.items, isNotEmpty);
    });
  });
}
