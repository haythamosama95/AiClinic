import 'package:supabase_flutter/supabase_flutter.dart';

import 'fake_postgrest_rpc.dart';

/// [SupabaseClient] fake for V1-6 billing repository and widget tests.
class BillingRpcTestClient extends RpcCaptureSupabaseClient {
  BillingRpcTestClient({Map<String, Map<String, dynamic>>? rpcResults}) : rpcResults = rpcResults ?? {};

  final Map<String, Map<String, dynamic>> rpcResults;
  final List<String> rpcLog = [];
  final List<Map<String, dynamic>> _draftItems = [];

  static const draftInvoiceId = '11111111-1111-4111-8111-111111111111';
  static const issuedInvoiceId = '22222222-2222-4222-8222-222222222222';
  static const visitId = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
  static const itemId = '33333333-3333-4333-8333-333333333333';

  @override
  PostgrestFilterBuilder<T> rpc<T>(String fn, {Map<String, dynamic>? params, dynamic get = false}) {
    rpcLog.add(fn);
    lastFunction = fn;
    lastParams = params == null ? null : Map<String, dynamic>.from(params);
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
      _ => {'success': true, 'data': {}},
    };
  }

  Map<String, dynamic> _detailFor(String invoiceId) {
    final isIssued = invoiceId == issuedInvoiceId;
    return {
      'invoice': {
        'id': invoiceId,
        'invoice_number': isIssued ? 'INV-MAIN-000001' : null,
        'status': isIssued ? 'issued' : 'draft',
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
        'balance': isIssued ? '100.00' : '0',
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
      'payments': [],
      'patient': {'id': 'cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'display_name': 'Test Patient'},
      'branch': {'id': '44444444-4444-4444-8444-444444444444', 'code': 'MAIN', 'name': 'Main'},
      'insurance_provider': null,
    };
  }
}
