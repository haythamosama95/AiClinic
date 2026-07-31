import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/billing/data/payment_repository.dart';
import 'package:ai_clinic/features/billing/domain/payment_method.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/billing_rpc_test_client.dart';

void main() {
  late BillingRpcTestClient client;
  late PaymentRepository repo;

  setUp(() {
    client = BillingRpcTestClient();
    repo = PaymentRepository(client);
  });

  group('PaymentRepository recordPayment', () {
    test('returns payment id and forwards trimmed params', () async {
      client.allowPartialPayments = true;

      final paymentId = await repo.recordPayment(
        invoiceId: '  ${BillingRpcTestClient.issuedInvoiceId}  ',
        method: PaymentMethod.card,
        amount: ' 50.00 ',
        note: 'Front desk',
      );

      expect(paymentId, 'pay-1');
      expect(client.lastFunction, 'record_payment');
      expect(client.lastParams?['p_invoice_id'], BillingRpcTestClient.issuedInvoiceId);
      expect(client.lastParams?['p_method'], 'card');
      expect(client.lastParams?['p_amount'], '50.00');
      expect(client.lastParams?['p_note'], 'Front desk');
    });

    test('rejects empty invoiceId before RPC', () {
      expect(
        () => repo.recordPayment(
          invoiceId: '   ',
          method: PaymentMethod.cash,
          amount: '10',
        ),
        throwsA(isA<RpcFailure>().having((error) => error.code, 'code', 'INVALID_INPUT')),
      );
      expect(client.rpcLog, isEmpty);
    });

    test('rejects zero amount before RPC', () {
      expect(
        () => repo.recordPayment(
          invoiceId: BillingRpcTestClient.issuedInvoiceId,
          method: PaymentMethod.cash,
          amount: '0',
        ),
        throwsA(
          isA<RpcFailure>().having(
            (error) => error.message,
            'message',
            'Amount must be greater than zero.',
          ),
        ),
      );
      expect(client.rpcLog, isEmpty);
    });

    test('rejects negative amount before RPC', () {
      expect(
        () => repo.recordPayment(
          invoiceId: BillingRpcTestClient.issuedInvoiceId,
          method: PaymentMethod.cash,
          amount: '-5',
        ),
        throwsA(
          isA<RpcFailure>().having(
            (error) => error.message,
            'message',
            'Amount must be greater than zero.',
          ),
        ),
      );
      expect(client.rpcLog, isEmpty);
    });

    test('rejects non-numeric amount before RPC', () {
      expect(
        () => repo.recordPayment(
          invoiceId: BillingRpcTestClient.issuedInvoiceId,
          method: PaymentMethod.cash,
          amount: 'abc',
        ),
        throwsA(
          isA<RpcFailure>().having(
            (error) => error.message,
            'message',
            'Amount must be greater than zero.',
          ),
        ),
      );
      expect(client.rpcLog, isEmpty);
    });

    test('throws StateError when payment_id is missing', () async {
      client = BillingRpcTestClient(
        rpcResults: {
          'record_payment': {'success': true, 'data': null},
        },
      );
      repo = PaymentRepository(client);

      expect(
        () => repo.recordPayment(
          invoiceId: BillingRpcTestClient.issuedInvoiceId,
          method: PaymentMethod.cash,
          amount: '10',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('propagates OVERPAYMENT from server rules', () async {
      expect(
        () => repo.recordPayment(
          invoiceId: BillingRpcTestClient.issuedInvoiceId,
          method: PaymentMethod.cash,
          amount: '150.00',
        ),
        throwsA(isA<RpcFailure>().having((error) => error.code, 'code', 'OVERPAYMENT')),
      );
    });

    test('propagates PARTIAL_PAYMENTS_DISABLED from server rules', () async {
      client.allowPartialPayments = false;

      expect(
        () => repo.recordPayment(
          invoiceId: BillingRpcTestClient.issuedInvoiceId,
          method: PaymentMethod.cash,
          amount: '50.00',
        ),
        throwsA(
          isA<RpcFailure>().having((error) => error.code, 'code', 'PARTIAL_PAYMENTS_DISABLED'),
        ),
      );
    });

    test('propagates INVOICE_VOIDED from server rules', () async {
      client.issuedStatus = 'voided';

      expect(
        () => repo.recordPayment(
          invoiceId: BillingRpcTestClient.issuedInvoiceId,
          method: PaymentMethod.cash,
          amount: '10',
        ),
        throwsA(isA<RpcFailure>().having((error) => error.code, 'code', 'INVOICE_VOIDED')),
      );
    });
  });

  group('PaymentRepository recordRefund', () {
    setUp(() {
      client.payments.add({
        'id': 'pay-1',
        'method': 'card',
        'amount': '80.00',
        'note': null,
        'recorded_by': {'id': 'staff-1', 'display_name': 'Reception'},
        'recorded_at': '2026-06-01T12:00:00.000Z',
      });
    });

    test('returns payment id and forwards trimmed params', () async {
      final paymentId = await repo.recordRefund(
        invoiceId: '  ${BillingRpcTestClient.issuedInvoiceId}  ',
        method: PaymentMethod.bankTransfer,
        amount: ' 25.00 ',
        note: '  Patient overpaid  ',
      );

      expect(paymentId, 'ref-2');
      expect(client.lastFunction, 'record_refund');
      expect(client.lastParams?['p_invoice_id'], BillingRpcTestClient.issuedInvoiceId);
      expect(client.lastParams?['p_method'], 'bank_transfer');
      expect(client.lastParams?['p_amount'], '25.00');
      expect(client.lastParams?['p_note'], 'Patient overpaid');
    });

    test('rejects empty note before RPC', () {
      expect(
        () => repo.recordRefund(
          invoiceId: BillingRpcTestClient.issuedInvoiceId,
          method: PaymentMethod.cash,
          amount: '10',
          note: '   ',
        ),
        throwsA(isA<RpcFailure>().having((error) => error.code, 'code', 'INVALID_INPUT')),
      );
      expect(client.rpcLog, isEmpty);
    });

    test('rejects zero amount before RPC', () {
      expect(
        () => repo.recordRefund(
          invoiceId: BillingRpcTestClient.issuedInvoiceId,
          method: PaymentMethod.cash,
          amount: '0',
          note: 'Correction',
        ),
        throwsA(
          isA<RpcFailure>().having(
            (error) => error.message,
            'message',
            'Amount must be greater than zero.',
          ),
        ),
      );
      expect(client.rpcLog, isEmpty);
    });

    test('rejects negative amount before RPC', () {
      expect(
        () => repo.recordRefund(
          invoiceId: BillingRpcTestClient.issuedInvoiceId,
          method: PaymentMethod.cash,
          amount: '-5',
          note: 'Correction',
        ),
        throwsA(
          isA<RpcFailure>().having(
            (error) => error.message,
            'message',
            'Amount must be greater than zero.',
          ),
        ),
      );
      expect(client.rpcLog, isEmpty);
    });

    test('rejects non-numeric amount before RPC', () {
      expect(
        () => repo.recordRefund(
          invoiceId: BillingRpcTestClient.issuedInvoiceId,
          method: PaymentMethod.cash,
          amount: 'abc',
          note: 'Correction',
        ),
        throwsA(
          isA<RpcFailure>().having(
            (error) => error.message,
            'message',
            'Amount must be greater than zero.',
          ),
        ),
      );
      expect(client.rpcLog, isEmpty);
    });

    test('throws StateError when payment_id is missing', () async {
      client = BillingRpcTestClient(
        rpcResults: {
          'record_refund': {'success': true, 'data': null},
        },
      );
      client.payments.add({
        'id': 'pay-1',
        'method': 'card',
        'amount': '80.00',
        'note': null,
        'recorded_by': {'id': 'staff-1', 'display_name': 'Reception'},
        'recorded_at': '2026-06-01T12:00:00.000Z',
      });
      repo = PaymentRepository(client);

      expect(
        () => repo.recordRefund(
          invoiceId: BillingRpcTestClient.issuedInvoiceId,
          method: PaymentMethod.cash,
          amount: '10',
          note: 'Correction',
        ),
        throwsA(isA<StateError>()),
      );
    });
  });
}
