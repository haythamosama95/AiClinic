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
  String? issuedVoidReason;
  String? draftInvoiceDiscountKind;
  String? draftInvoiceDiscountValue;
  String draftInvoiceDiscountAmount = '0';
  final List<Map<String, dynamic>> insuranceProviders = [
    {
      'id': '99999999-9999-4999-8999-999999999999',
      'name': 'Acme Insurance',
      'contact_info': 'claims@acme.test',
      'is_active': true,
    },
  ];
  String? draftInsuranceProviderId;
  String draftInsuranceCoveredAmount = '0';
  String? draftInsuranceProviderName;
  final List<Map<String, dynamic>> catalogInvoices = [
    {
      'id': '22222222-2222-4222-8222-222222222222',
      'invoice_number': 'INV-MAIN-000001',
      'status': 'issued',
      'patient_display_name': 'Test Patient',
      'branch_code': 'MAIN',
      'branch_id': '44444444-4444-4444-8444-444444444444',
      'patient_id': 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
      'subtotal': '100',
      'discount_amount': '0',
      'insurance_covered_amount': '0',
      'paid_amount': '0',
      'balance': '100.00',
      'created_at': '2026-06-02T10:00:00.000Z',
      'issued_at': '2026-06-02T11:00:00.000Z',
    },
    {
      'id': '55555555-5555-4555-8555-555555555555',
      'invoice_number': 'INV-MAIN-000002',
      'status': 'paid',
      'patient_display_name': 'Test Patient',
      'branch_code': 'MAIN',
      'branch_id': '44444444-4444-4444-8444-444444444444',
      'patient_id': 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
      'subtotal': '80',
      'discount_amount': '0',
      'insurance_covered_amount': '0',
      'paid_amount': '80.00',
      'balance': '0.00',
      'created_at': '2026-06-01T10:00:00.000Z',
      'issued_at': '2026-06-01T11:00:00.000Z',
    },
    {
      'id': '66666666-6666-4666-8666-666666666666',
      'invoice_number': 'INV-SIDE-000001',
      'status': 'issued',
      'patient_display_name': 'Other Patient',
      'branch_code': 'SIDE',
      'branch_id': '77777777-7777-4777-8777-777777777777',
      'patient_id': 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
      'subtotal': '60',
      'discount_amount': '0',
      'insurance_covered_amount': '0',
      'paid_amount': '0',
      'balance': '60.00',
      'created_at': '2026-06-03T10:00:00.000Z',
      'issued_at': '2026-06-03T11:00:00.000Z',
    },
  ];

  static const draftInvoiceId = '11111111-1111-4111-8111-111111111111';
  static const insuranceProviderId = '99999999-9999-4999-8999-999999999999';
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
      'list_invoices' => _listInvoices(),
      'list_patient_invoices' => _listPatientInvoices(),
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
      'apply_line_discount' => _applyLineDiscount(),
      'apply_invoice_discount' => _applyInvoiceDiscount(),
      'list_insurance_providers' => _listInsuranceProviders(),
      'set_insurance_coverage' => _setInsuranceCoverage(),
      'insurance_provider_upsert' => _insuranceProviderUpsert(),
      'insurance_provider_deactivate' => _insuranceProviderDeactivate(),
      'void_invoice' => _voidInvoice(),
      _ => {'success': true, 'data': {}},
    };
  }

  Map<String, dynamic> _listInvoices() {
    final filters = lastParams?['p_filters'];
    final visitFilter = filters is Map ? filters['visit_id']?.toString() : null;
    if (visitFilter == visitId) {
      final visitRows = [
        {
          'id': 'voided-visit-invoice',
          'invoice_number': 'INV-MAIN-VOIDED',
          'status': 'voided',
          'patient_display_name': 'Test Patient',
          'branch_code': 'MAIN',
          'subtotal': '0',
          'discount_amount': '0',
          'insurance_covered_amount': '0',
          'paid_amount': '0',
          'balance': '0',
          'created_at': '2026-06-02T10:00:00.000Z',
          'issued_at': '2026-06-02T11:00:00.000Z',
        },
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
      ];
      final statuses = filters is Map ? filters['statuses'] : null;
      final filtered = statuses is List && statuses.isNotEmpty
          ? visitRows.where((row) => statuses.map((s) => s.toString()).contains(row['status'])).toList(growable: false)
          : visitRows;
      return {
        'success': true,
        'data': {'items': filtered.take(1).toList(growable: false)},
      };
    }

    final limit = (lastParams?['p_limit'] as int?) ?? 50;
    final offset = (lastParams?['p_offset'] as int?) ?? 0;
    final filtered = _filterCatalogInvoices(filters);
    final page = filtered.skip(offset).take(limit).toList(growable: false);
    return {
      'success': true,
      'data': {'items': page},
    };
  }

  Map<String, dynamic> _listPatientInvoices() {
    final patientId = lastParams?['p_patient_id']?.toString();
    final limit = (lastParams?['p_limit'] as int?) ?? 50;
    final offset = (lastParams?['p_offset'] as int?) ?? 0;
    final filtered = catalogInvoices.where((row) => row['patient_id']?.toString() == patientId).toList(growable: false);
    final page = filtered.skip(offset).take(limit).toList(growable: false);
    return {
      'success': true,
      'data': {'items': page},
    };
  }

  List<Map<String, dynamic>> _filterCatalogInvoices(Object? filters) {
    if (filters is! Map) {
      return List<Map<String, dynamic>>.from(catalogInvoices);
    }

    Iterable<Map<String, dynamic>> rows = catalogInvoices;
    final statuses = filters['statuses'];
    if (statuses is List && statuses.isNotEmpty) {
      final allowed = statuses.map((value) => value.toString()).toSet();
      rows = rows.where((row) => allowed.contains(row['status']?.toString()));
    }

    final branchIds = filters['branch_ids'];
    if (branchIds is List && branchIds.isNotEmpty) {
      final allowed = branchIds.map((value) => value.toString()).toSet();
      rows = rows.where((row) => allowed.contains(row['branch_id']?.toString()));
    }

    final patientSearch = filters['patient_search']?.toString().trim();
    if (patientSearch != null && patientSearch.isNotEmpty) {
      final needle = patientSearch.toLowerCase();
      rows = rows.where((row) => row['patient_display_name']?.toString().toLowerCase().contains(needle) ?? false);
    }

    final invoiceNumber = filters['invoice_number']?.toString().trim();
    if (invoiceNumber != null && invoiceNumber.isNotEmpty) {
      rows = rows.where((row) {
        final number = row['invoice_number']?.toString() ?? '';
        return number == invoiceNumber || number.startsWith(invoiceNumber);
      });
    }

    final sorted = rows.toList(growable: false)
      ..sort((a, b) => (b['created_at']?.toString() ?? '').compareTo(a['created_at']?.toString() ?? ''));
    return sorted;
  }

  Map<String, dynamic> _voidInvoice() {
    final invoiceId = lastParams?['p_invoice_id']?.toString() ?? issuedInvoiceId;
    final reason = lastParams?['p_reason']?.toString() ?? '';

    if (invoiceId != issuedInvoiceId) {
      return {'success': false, 'error_code': 'NOT_FOUND', 'error_message': 'Invoice not found.'};
    }

    if (reason.trim().isEmpty) {
      return {'success': false, 'error_code': 'INVALID_INPUT', 'error_message': 'Reason required.'};
    }

    if (issuedStatus == 'voided') {
      return {'success': false, 'error_code': 'INVOICE_VOIDED', 'error_message': 'Already voided.'};
    }

    if (issuedStatus == 'paid') {
      return {'success': false, 'error_code': 'INVOICE_NOT_VOIDABLE', 'error_message': 'Refund paid invoices first.'};
    }

    if (issuedStatus != 'issued' && issuedStatus != 'partially_paid') {
      return {'success': false, 'error_code': 'INVOICE_NOT_VOIDABLE', 'error_message': 'Invoice cannot be voided.'};
    }

    issuedStatus = 'voided';
    issuedVoidReason = reason.trim();
    issuedBalance = '0.00';
    return {
      'success': true,
      'data': {'invoice_id': invoiceId},
    };
  }

  Map<String, dynamic> _recordPayment() {
    final invoiceId = lastParams?['p_invoice_id']?.toString() ?? issuedInvoiceId;
    if (invoiceId != issuedInvoiceId) {
      return {'success': false, 'error_code': 'NOT_FOUND', 'error_message': 'Invoice not found.'};
    }

    if (issuedStatus == 'voided') {
      return {'success': false, 'error_code': 'INVOICE_VOIDED', 'error_message': 'Invoice is voided.'};
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

  bool _hasLineDiscountScope() {
    return _draftItems.any(
      (item) =>
          item['line_discount_kind'] != null ||
          (double.tryParse(item['line_discount_amount']?.toString() ?? '') ?? 0) > 0,
    );
  }

  bool _hasInvoiceDiscountScope() {
    return draftInvoiceDiscountKind != null || (double.tryParse(draftInvoiceDiscountAmount) ?? 0) > 0;
  }

  Map<String, dynamic> _applyLineDiscount() {
    final targetItemId = lastParams?['p_item_id']?.toString() ?? BillingRpcTestClient.itemId;
    final kind = lastParams?['p_kind'];
    final value = lastParams?['p_value'];

    final index = _draftItems.indexWhere((row) => row['id']?.toString() == targetItemId);
    if (index < 0) {
      return {'success': false, 'error_code': 'NOT_FOUND', 'error_message': 'Item not found.'};
    }

    final item = Map<String, dynamic>.from(_draftItems[index]);
    final lineSubtotal = double.tryParse(item['line_subtotal']?.toString() ?? '') ?? 0;
    final hasLineDiscount =
        item['line_discount_kind'] != null ||
        (double.tryParse(item['line_discount_amount']?.toString() ?? '') ?? 0) > 0;

    if (kind == null && value == null && !hasLineDiscount) {
      return {
        'success': true,
        'data': {'item_id': targetItemId},
      };
    }

    if (_hasInvoiceDiscountScope()) {
      return {
        'success': false,
        'error_code': 'DISCOUNT_SCOPE_CONFLICT',
        'error_message': 'Discount scopes are mutually exclusive — clear the invoice-level discount first.',
      };
    }

    if (kind == null && value == null) {
      item
        ..['line_discount_kind'] = null
        ..['line_discount_value'] = null
        ..['line_discount_amount'] = '0'
        ..['line_total'] = item['line_subtotal'];
    } else {
      final parsedValue = double.tryParse(value?.toString() ?? '') ?? -1;
      if (kind == 'percentage') {
        if (parsedValue < 0 || parsedValue > 100) {
          return {'success': false, 'error_code': 'INVALID_INPUT', 'error_message': 'Invalid percentage.'};
        }
        final amount = (lineSubtotal * parsedValue / 100).toStringAsFixed(2);
        item
          ..['line_discount_kind'] = kind
          ..['line_discount_value'] = value?.toString()
          ..['line_discount_amount'] = amount
          ..['line_total'] = (lineSubtotal - double.parse(amount)).toStringAsFixed(2);
      } else if (kind == 'fixed') {
        if (parsedValue < 0 || parsedValue > lineSubtotal) {
          return {'success': false, 'error_code': 'INVALID_INPUT', 'error_message': 'Invalid fixed discount.'};
        }
        item
          ..['line_discount_kind'] = kind
          ..['line_discount_value'] = value?.toString()
          ..['line_discount_amount'] = parsedValue.toStringAsFixed(2)
          ..['line_total'] = (lineSubtotal - parsedValue).toStringAsFixed(2);
      }
    }

    _draftItems[index] = item;
    return {
      'success': true,
      'data': {'item_id': targetItemId},
    };
  }

  Map<String, dynamic> _applyInvoiceDiscount() {
    final kind = lastParams?['p_kind'];
    final value = lastParams?['p_value'];

    if (_hasLineDiscountScope()) {
      return {
        'success': false,
        'error_code': 'DISCOUNT_SCOPE_CONFLICT',
        'error_message': 'Discount scopes are mutually exclusive — clear all line-level discounts first.',
      };
    }

    final subtotal = _draftItems.fold<double>(0, (sum, row) {
      return sum + (double.tryParse(row['line_total']?.toString() ?? '') ?? 0);
    });

    if (kind == null && value == null) {
      draftInvoiceDiscountKind = null;
      draftInvoiceDiscountValue = null;
      draftInvoiceDiscountAmount = '0';
    } else {
      final parsedValue = double.tryParse(value?.toString() ?? '') ?? -1;
      if (kind == 'percentage') {
        if (parsedValue < 0 || parsedValue > 100) {
          return {'success': false, 'error_code': 'INVALID_INPUT', 'error_message': 'Invalid percentage.'};
        }
        draftInvoiceDiscountKind = kind?.toString();
        draftInvoiceDiscountValue = value?.toString();
        draftInvoiceDiscountAmount = (subtotal * parsedValue / 100).toStringAsFixed(2);
      } else if (kind == 'fixed') {
        if (parsedValue < 0 || parsedValue > subtotal) {
          return {'success': false, 'error_code': 'INVALID_INPUT', 'error_message': 'Invalid fixed discount.'};
        }
        draftInvoiceDiscountKind = kind?.toString();
        draftInvoiceDiscountValue = value?.toString();
        draftInvoiceDiscountAmount = parsedValue.toStringAsFixed(2);
      }
    }

    return {
      'success': true,
      'data': {'invoice_id': draftInvoiceId, 'discount_amount': draftInvoiceDiscountAmount},
    };
  }

  Map<String, dynamic> _listInsuranceProviders() {
    final onlyActive = lastParams?['p_only_active'] != false;
    final rows = insuranceProviders.where((row) => !onlyActive || row['is_active'] == true).toList(growable: false);
    return {
      'success': true,
      'data': {'providers': rows},
    };
  }

  Map<String, dynamic> _setInsuranceCoverage() {
    final invoiceId = lastParams?['p_invoice_id']?.toString() ?? draftInvoiceId;
    if (invoiceId != draftInvoiceId) {
      return {'success': false, 'error_code': 'NOT_FOUND', 'error_message': 'Invoice not found.'};
    }

    final providerId = lastParams?['p_provider_id']?.toString();
    final amount = double.tryParse(lastParams?['p_covered_amount']?.toString() ?? '') ?? 0;
    final subtotal = _draftItems.fold<double>(0, (sum, row) {
      return sum + (double.tryParse(row['line_total']?.toString() ?? '') ?? 0);
    });
    final discount = double.tryParse(draftInvoiceDiscountAmount) ?? 0;
    final netTotal = subtotal - discount;

    if (providerId == null && amount == 0) {
      draftInsuranceProviderId = null;
      draftInsuranceCoveredAmount = '0';
      draftInsuranceProviderName = null;
      return {'success': true, 'data': {}};
    }

    if (providerId == null) {
      return {'success': false, 'error_code': 'INVALID_INPUT', 'error_message': 'Provider required.'};
    }

    if (amount < 0 || amount > netTotal) {
      return {'success': false, 'error_code': 'INVALID_INPUT', 'error_message': 'Invalid covered amount.'};
    }

    final provider = insuranceProviders.cast<Map<String, dynamic>?>().firstWhere(
      (row) => row?['id']?.toString() == providerId,
      orElse: () => null,
    );
    if (provider == null || provider['is_active'] != true) {
      return {'success': false, 'error_code': 'NOT_FOUND', 'error_message': 'Provider not found.'};
    }

    draftInsuranceProviderId = providerId;
    draftInsuranceCoveredAmount = amount.toStringAsFixed(2);
    draftInsuranceProviderName = provider['name']?.toString();
    return {'success': true, 'data': {}};
  }

  Map<String, dynamic> _insuranceProviderUpsert() {
    final id = lastParams?['p_id']?.toString();
    final name = lastParams?['p_name']?.toString() ?? '';
    final contact = lastParams?['p_contact_info']?.toString();
    if (name.trim().isEmpty) {
      return {'success': false, 'error_code': 'INVALID_INPUT', 'error_message': 'Name required.'};
    }

    if (id != null) {
      final index = insuranceProviders.indexWhere((row) => row['id']?.toString() == id);
      if (index < 0) {
        return {'success': false, 'error_code': 'NOT_FOUND', 'error_message': 'Provider not found.'};
      }
      insuranceProviders[index] = {...insuranceProviders[index], 'name': name, 'contact_info': contact};
      return {
        'success': true,
        'data': {'provider_id': id},
      };
    }

    final providerId = 'prov-${insuranceProviders.length + 1}';
    insuranceProviders.add({'id': providerId, 'name': name, 'contact_info': contact, 'is_active': true});
    return {
      'success': true,
      'data': {'provider_id': providerId},
    };
  }

  Map<String, dynamic> _insuranceProviderDeactivate() {
    final id = lastParams?['p_id']?.toString();
    final index = insuranceProviders.indexWhere((row) => row['id']?.toString() == id);
    if (index < 0) {
      return {'success': false, 'error_code': 'NOT_FOUND', 'error_message': 'Provider not found.'};
    }
    insuranceProviders[index] = {...insuranceProviders[index], 'is_active': false};
    return {
      'success': true,
      'data': {'provider_id': id},
    };
  }

  Map<String, dynamic> _detailFor(String invoiceId) {
    final isIssued = invoiceId == issuedInvoiceId;
    final draftSubtotal = _draftItems
        .fold<double>(0, (sum, row) {
          return sum + (double.tryParse(row['line_total']?.toString() ?? '') ?? 0);
        })
        .toStringAsFixed(2);
    return {
      'invoice': {
        'id': invoiceId,
        'invoice_number': isIssued ? 'INV-MAIN-000001' : null,
        'status': isIssued ? issuedStatus : 'draft',
        'branch_id': '44444444-4444-4444-8444-444444444444',
        'patient_id': 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
        'visit_id': visitId,
        'subtotal': isIssued ? '100.00' : draftSubtotal,
        'discount_kind': isIssued ? null : draftInvoiceDiscountKind,
        'discount_value': isIssued ? null : draftInvoiceDiscountValue,
        'discount_amount': isIssued ? '0' : draftInvoiceDiscountAmount,
        'insurance_provider_id': isIssued ? null : draftInsuranceProviderId,
        'insurance_covered_amount': isIssued ? '0' : draftInsuranceCoveredAmount,
        'currency': 'USD',
        'issued_at': isIssued ? '2026-06-01T11:00:00.000Z' : null,
        'voided_at': isIssued && issuedStatus == 'voided' ? DateTime.now().toUtc().toIso8601String() : null,
        'void_reason': isIssued ? issuedVoidReason : null,
        'balance': isIssued
            ? issuedBalance
            : (double.parse(draftSubtotal) - (double.tryParse(draftInsuranceCoveredAmount) ?? 0)).toStringAsFixed(2),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
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
      'insurance_provider': isIssued || draftInsuranceProviderId == null
          ? null
          : {'id': draftInsuranceProviderId, 'name': draftInsuranceProviderName},
    };
  }
}
