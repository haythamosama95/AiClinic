import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/billing/data/invoice_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/billing_rpc_test_client.dart';

void main() {
  late BillingRpcTestClient client;
  late InvoiceRepository repo;

  setUp(() {
    client = BillingRpcTestClient();
    repo = InvoiceRepository(client);
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
}
