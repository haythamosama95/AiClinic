import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/billing/application/billing_rpc_messages.dart';
import 'package:flutter_test/flutter_test.dart';

RpcFailure _failure({required String code, String message = 'backend message'}) {
  return RpcFailure(RpcResult(success: false, errorCode: code, errorMessage: message));
}

void main() {
  group('billingMessageForRpc', () {
    test('STALE_INVOICE returns reload message', () {
      expect(
        billingMessageForRpc(_failure(code: 'STALE_INVOICE')),
        'This invoice was updated elsewhere. Reload and try again.',
      );
    });

    test('ACTIVE_INVOICE_EXISTS returns duplicate message', () {
      expect(
        billingMessageForRpc(_failure(code: 'ACTIVE_INVOICE_EXISTS')),
        'This visit already has an active invoice.',
      );
    });

    test('VISIT_NOT_COMPLETED returns completed-visit message', () {
      expect(
        billingMessageForRpc(_failure(code: 'VISIT_NOT_COMPLETED')),
        'Invoices can only be created from completed visits.',
      );
    });

    test('BRANCH_CODE_MISSING returns branch code guidance', () {
      expect(
        billingMessageForRpc(_failure(code: 'BRANCH_CODE_MISSING')),
        'Assign a branch code in Settings before issuing invoices.',
      );
    });

    test('NO_ITEMS returns line item guidance', () {
      expect(
        billingMessageForRpc(_failure(code: 'NO_ITEMS')),
        'Add at least one line item before issuing.',
      );
    });

    test('INVOICE_NOT_IN_DRAFT returns edit lock message', () {
      expect(
        billingMessageForRpc(_failure(code: 'INVOICE_NOT_IN_DRAFT')),
        'This invoice can no longer be edited.',
      );
    });

    test('OVERPAYMENT returns balance message', () {
      expect(billingMessageForRpc(_failure(code: 'OVERPAYMENT')), 'Payment amount exceeds the current balance.');
    });

    test('PARTIAL_PAYMENTS_DISABLED returns full-balance message', () {
      expect(
        billingMessageForRpc(_failure(code: 'PARTIAL_PAYMENTS_DISABLED')),
        contains('Partial payments are not allowed'),
      );
    });

    test('INVOICE_VOIDED returns voided payment message', () {
      expect(
        billingMessageForRpc(_failure(code: 'INVOICE_VOIDED')),
        'This invoice is voided and cannot accept payments.',
      );
    });

    test('INVOICE_NOT_VOIDABLE returns void eligibility message', () {
      expect(
        billingMessageForRpc(_failure(code: 'INVOICE_NOT_VOIDABLE')),
        'Only issued or partially paid invoices can be voided. Refund paid invoices first.',
      );
    });

    test('INVOICE_NOT_PAYABLE returns payable state message', () {
      expect(
        billingMessageForRpc(_failure(code: 'INVOICE_NOT_PAYABLE')),
        'Payments cannot be recorded on this invoice in its current state.',
      );
    });

    test('DISCOUNT_SCOPE_CONFLICT returns mutual exclusion message', () {
      expect(billingMessageForRpc(_failure(code: 'DISCOUNT_SCOPE_CONFLICT')), contains('mutually exclusive'));
    });

    test('FORBIDDEN returns billing permission message', () {
      expect(
        billingMessageForRpc(_failure(code: 'FORBIDDEN')),
        'You do not have permission to perform this billing action.',
      );
    });

    test('unknown code falls back to backend message', () {
      expect(
        billingMessageForRpc(_failure(code: 'CUSTOM', message: 'Custom backend detail.')),
        'Custom backend detail.',
      );
    });

    test('unknown code with empty message uses generic fallback', () {
      expect(billingMessageForRpc(_failure(code: 'CUSTOM', message: '')), 'Something went wrong. Please try again.');
    });

    test('INVALID_INPUT uses backend message when present', () {
      expect(
        billingMessageForRpc(_failure(code: 'INVALID_INPUT', message: 'Description must be 500 characters or fewer.')),
        'Description must be 500 characters or fewer.',
      );
    });

    test('INVALID_INPUT with empty message uses generic billing fallback', () {
      expect(
        billingMessageForRpc(_failure(code: 'INVALID_INPUT', message: '')),
        'The billing input was invalid. Check the form and try again.',
      );
    });

    test('NOT_FOUND returns friendly message', () {
      expect(billingMessageForRpc(_failure(code: 'NOT_FOUND')), 'The requested billing record was not found.');
    });

    test('RPC_NOT_APPLIED returns retry message', () {
      expect(
        billingMessageForRpc(_failure(code: 'RPC_NOT_APPLIED')),
        'The billing action could not be applied. Please try again.',
      );
    });

    test('RPC_NOT_CONFIGURED returns administrator message', () {
      expect(
        billingMessageForRpc(_failure(code: 'RPC_NOT_CONFIGURED')),
        'Billing is not configured correctly. Contact your administrator.',
      );
    });

    test('AUTH_ERROR returns session message', () {
      expect(
        billingMessageForRpc(_failure(code: 'AUTH_ERROR')),
        'Your session has expired or is invalid. Sign in again and retry.',
      );
    });

    test('UNEXPECTED_RESPONSE returns refresh guidance', () {
      expect(
        billingMessageForRpc(_failure(code: 'UNEXPECTED_RESPONSE')),
        'Billing data from the server was incomplete. Please refresh and try again.',
      );
    });
  });
}
