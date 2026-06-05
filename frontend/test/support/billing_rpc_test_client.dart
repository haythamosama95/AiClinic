import 'package:supabase_flutter/supabase_flutter.dart';

import 'fake_postgrest_rpc.dart';

/// [SupabaseClient] fake for V1-6 billing repository and widget tests.
class BillingRpcTestClient extends RpcCaptureSupabaseClient {
  BillingRpcTestClient({Map<String, Map<String, dynamic>>? rpcResults}) : rpcResults = rpcResults ?? {};

  final Map<String, Map<String, dynamic>> rpcResults;
  final List<String> rpcLog = [];
  final List<Map<String, dynamic>> _draftItems = [];
  final List<Map<String, dynamic>> payments = [];

  bool allowPartialPayments = false;
  String issuedBalance = '100.00';
  String issuedStatus = 'issued';

  static const draftInvoiceId = '11111111-1111-4111-8111-111111111111';
  static const issuedInvoiceId = '22222222-2222-4222-8222-222222222222';
  static const visitId = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
  static const itemId = '33333333-3333-4333-8333-333333333333';

  @override
  PostgrestFilterBuilder<T> rpc<T>(String fn, {Map<String, dynamic>? params, dynamic get = false}) {
    rpcLog.add(fn);
    lastFunction = fn;
    lastParams = params == null ? null : Map<String, dynamic>.from(params);
    if (fn == 'update_billing_settings') {
      allowPartialPayments = lastParams?['p_allow_partial_payments'] == true;
    }
    final override = rpcResults[fn];
    final payload = override ?? _defaultPayload(fn);
    return FakePostgrestRpc(payload) as PostgrestFilterBuilder<T>;
  }

  Map<String, dynamic> _defaultPayload(String fn) {
    return switch (fn) {
      'create_invoice_from_visit' => {
        'success': true,
        'data': {'invoice_id': draftInvoiceId},
      },
      'get_invoice_detail' => {
        'success': true,
        'data': _detailFor(lastParams?['p_invoice_id']?.toString() ?? draftInvoiceId),
      },
      'list_invoices' => {
        'success': true,
        'data': {
          'items': lastParams?['p_filters']?['visit_id'] == visitId
              ? [
                  {
                    'id': draftInvoiceId,
                    'invoice_number': null,
                    'status': 'draft',
                    'patient_display_name': 'Test Patient',
                    'branch_code': 'MAIN',
                    'subtotal': '0',
                    'discount_amount': '0',
                    'insurance_covered_amount': '0',
                    'paid_amount': '0',
                    'balance': '0',
                    'created_at': '2026-06-01T10:00:00.000Z',
                    'issued_at': null,
                  },
                ]
              : [],
        },
      },
      'add_invoice_item' => () {
        _draftItems.add({
          'id': itemId,
          'description': lastParams?['p_description']?.toString() ?? 'Item',
          'quantity': lastParams?['p_quantity']?.toString() ?? '1',
          'unit_price': lastParams?['p_unit_price']?.toString() ?? '0',
          'line_subtotal': lastParams?['p_unit_price']?.toString() ?? '0',
          'line_discount_kind': null,
          'line_discount_value': null,
          'line_discount_amount': '0',
          'line_total': lastParams?['p_unit_price']?.toString() ?? '0',
        });
        return {
          'success': true,
          'data': {'item_id': itemId},
        };
      }(),
      'update_invoice_item' => {
        'success': true,
        'data': {'item_id': lastParams?['p_item_id']},
      },
      'remove_invoice_item' => {
        'success': true,
        'data': {'item_id': lastParams?['p_item_id']},
      },
      'issue_invoice' => {
        'success': true,
        'data': {'invoice_number': 'INV-MAIN-000001'},
      },
      'get_billing_settings' => {
        'success': true,
        'data': {'allow_partial_payments': allowPartialPayments},
      },
      'update_billing_settings' => {
        'success': true,
        'data': {'allow_partial_payments': lastParams?['p_allow_partial_payments'] == true},
      },
      'record_payment' => _recordPayment(),
      'record_refund' => _recordRefund(),
      _ => {'success': true, 'data': {}},
    };
  }

  Map<String, dynamic> _recordPayment() {
    final invoiceId = lastParams?['p_invoice_id']?.toString() ?? issuedInvoiceId;
    if (invoiceId != issuedInvoiceId) {
      return {'success': false, 'error_code': 'NOT_FOUND', 'error_message': 'Invoice not found.'};
    }

    final method = lastParams?['p_method']?.toString() ?? 'cash';
    final amount = double.tryParse(lastParams?['p_amount']?.toString() ?? '') ?? 0;
    final balance = double.tryParse(issuedBalance) ?? 0;

    if (amount <= 0) {
      return {'success': false, 'error_code': 'INVALID_INPUT', 'error_message': 'Invalid amount.'};
    }

    if (amount > balance) {
      return {'success': false, 'error_code': 'OVERPAYMENT', 'error_message': 'Payment exceeds balance.'};
    }

    final isPatientTender = method == 'cash' || method == 'card' || method == 'bank_transfer';
    if (!allowPartialPayments && isPatientTender && amount < balance) {
      return {
        'success': false,
        'error_code': 'PARTIAL_PAYMENTS_DISABLED',
        'error_message': 'Partial payments are not allowed for this organization; please collect the full balance.',
      };
    }

    final paymentId = 'pay-${payments.length + 1}';
    payments.add({
      'id': paymentId,
      'method': method,
      'amount': amount.toStringAsFixed(2),
      'reference': lastParams?['p_reference'],
      'note': lastParams?['p_note'],
      'recorded_by': 'staff-1',
      'recorded_at': DateTime.now().toUtc().toIso8601String(),
    });

    final newBalance = balance - amount;
    issuedBalance = newBalance.toStringAsFixed(2);
    issuedStatus = newBalance <= 0 ? 'paid' : 'partially_paid';

    return {
      'success': true,
      'data': {'payment_id': paymentId},
    };
  }

  Map<String, dynamic> _recordRefund() {
    final amount = double.tryParse(lastParams?['p_amount']?.toString() ?? '') ?? 0;
    final note = lastParams?['p_note']?.toString() ?? '';
    if (note.trim().isEmpty) {
      return {'success': false, 'error_code': 'INVALID_INPUT', 'error_message': 'Reason required.'};
    }

    final netPositive = payments.fold<double>(0, (sum, row) {
      final value = double.tryParse(row['amount']?.toString() ?? '') ?? 0;
      return value > 0 ? sum + value : sum;
    });

    if (amount <= 0 || amount > netPositive) {
      return {'success': false, 'error_code': 'INVALID_INPUT', 'error_message': 'Invalid refund amount.'};
    }

    final paymentId = 'ref-${payments.length + 1}';
    payments.add({
      'id': paymentId,
      'method': lastParams?['p_method']?.toString() ?? 'cash',
      'amount': (-amount).toStringAsFixed(2),
      'reference': null,
      'note': note,
      'recorded_by': 'staff-1',
      'recorded_at': DateTime.now().toUtc().toIso8601String(),
    });

    final balance = (double.tryParse(issuedBalance) ?? 0) + amount;
    issuedBalance = balance.toStringAsFixed(2);
    issuedStatus = balance >= 100 ? 'issued' : 'partially_paid';

    return {
      'success': true,
      'data': {'payment_id': paymentId},
    };
  }

  Map<String, dynamic> _detailFor(String invoiceId) {
    final isIssued = invoiceId == issuedInvoiceId;
    return {
      'invoice': {
        'id': invoiceId,
        'invoice_number': isIssued ? 'INV-MAIN-000001' : null,
        'status': isIssued ? issuedStatus : 'draft',
        'branch_id': '44444444-4444-4444-8444-444444444444',
        'patient_id': 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
        'visit_id': visitId,
        'subtotal': isIssued ? '100.00' : '0',
        'discount_kind': null,
        'discount_value': null,
        'discount_amount': '0',
        'insurance_provider_id': null,
        'insurance_covered_amount': '0',
        'currency': 'USD',
        'issued_at': isIssued ? '2026-06-01T11:00:00.000Z' : null,
        'voided_at': null,
        'void_reason': null,
        'balance': isIssued ? issuedBalance : '0',
        'updated_at': '2026-06-01T10:00:00.000Z',
      },
      'items': isIssued
          ? [
              {
                'id': itemId,
                'description': 'Consultation',
                'quantity': '1',
                'unit_price': '100',
                'line_subtotal': '100',
                'line_discount_kind': null,
                'line_discount_value': null,
                'line_discount_amount': '0',
                'line_total': '100',
              },
            ]
          : List<Map<String, dynamic>>.from(_draftItems),
      'payments': isIssued ? List<Map<String, dynamic>>.from(payments) : [],
      'patient': {'id': 'cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'display_name': 'Test Patient'},
      'branch': {'id': '44444444-4444-4444-8444-444444444444', 'code': 'MAIN', 'name': 'Main'},
      'insurance_provider': null,
    };
  }
}
