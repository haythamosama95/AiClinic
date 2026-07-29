import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/billing/data/payment_repository.dart';
import 'package:ai_clinic/features/billing/domain/payment_method.dart';
import 'package:ai_clinic/features/billing/presentation/providers/payment_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/billing_rpc_test_client.dart';

void main() {
  group('PaymentNotifier', () {
    late BillingRpcTestClient client;
    late ProviderContainer container;

    setUp(() {
      client = BillingRpcTestClient();
      container = ProviderContainer(
        overrides: [
          paymentRepositoryProvider.overrideWithValue(PaymentRepository(client)),
        ],
      );
    });

    tearDown(() {
      container.dispose();
    });

    PaymentNotifier readNotifier() => container.read(paymentNotifierProvider);

    test('recordPayment forwards trimmed arguments to the repository', () async {
      final paymentId = await readNotifier().recordPayment(
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

    test('recordRefund forwards trimmed arguments to the repository', () async {
      client.payments.add({
        'id': 'pay-1',
        'method': 'card',
        'amount': '80.00',
        'note': null,
        'recorded_by': {'id': 'staff-1', 'display_name': 'Reception'},
        'recorded_at': '2026-06-01T12:00:00.000Z',
      });

      final paymentId = await readNotifier().recordRefund(
        invoiceId: '  ${BillingRpcTestClient.issuedInvoiceId}  ',
        method: PaymentMethod.bankTransfer,
        amount: ' 25.00 ',
        note: '  Patient overpaid  ',
      );

      expect(paymentId, 'ref-1');
      expect(client.lastFunction, 'record_refund');
      expect(client.lastParams?['p_invoice_id'], BillingRpcTestClient.issuedInvoiceId);
      expect(client.lastParams?['p_method'], 'bank_transfer');
      expect(client.lastParams?['p_amount'], '25.00');
      expect(client.lastParams?['p_note'], 'Patient overpaid');
    });

    test('recordPayment propagates empty invoiceId validation errors', () {
      expect(
        () => readNotifier().recordPayment(
          invoiceId: '   ',
          method: PaymentMethod.cash,
          amount: '10',
        ),
        throwsA(isA<RpcFailure>().having((error) => error.code, 'code', 'INVALID_INPUT')),
      );
      expect(client.rpcLog, isEmpty);
    });

    test('recordPayment propagates zero amount validation errors', () {
      expect(
        () => readNotifier().recordPayment(
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

    test('recordPayment propagates negative amount validation errors', () {
      expect(
        () => readNotifier().recordPayment(
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

    test('recordRefund propagates missing note validation errors', () {
      expect(
        () => readNotifier().recordRefund(
          invoiceId: BillingRpcTestClient.issuedInvoiceId,
          method: PaymentMethod.cash,
          amount: '10',
          note: '   ',
        ),
        throwsA(isA<RpcFailure>().having((error) => error.code, 'code', 'INVALID_INPUT')),
      );
      expect(client.rpcLog, isEmpty);
    });
  });
}
