import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ai_clinic/core/config/supabase_config.dart' show supabaseClientProvider;
import 'package:ai_clinic/core/rpc/app_rpc_invoker.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/billing/domain/discount_kind.dart';
import 'package:ai_clinic/features/billing/domain/invoice_detail.dart';
import 'package:ai_clinic/features/billing/domain/invoice_list_item.dart';

/// Invoice billing RPC wrappers (V1-6).
class InvoiceRepository with AppRpcInvoker {
  InvoiceRepository(this._client);

  final SupabaseClient _client;

  @override
  SupabaseClient get rpcClient => _client;

  @override
  String get migrationHint => '20260605180500_billing_us1_rpcs.sql';

  @override
  String get rpcLogDomain => 'billing.invoices';

  Future<String> createFromVisit({required String visitId}) async {
    _assertNonEmpty('visitId', visitId);

    final result = await invokeRpc('create_invoice_from_visit', {'p_visit_id': visitId.trim()});
    final invoiceId = result.data?['invoice_id']?.toString() ?? result.data?.toString();
    if (invoiceId == null || invoiceId.isEmpty) {
      throw StateError('Create invoice returned an unexpected shape.');
    }
    return invoiceId;
  }

  Future<void> discardDraft({required String invoiceId, required DateTime expectedUpdatedAt}) async {
    _assertNonEmpty('invoiceId', invoiceId);

    await invokeRpc('discard_draft_invoice', {
      'p_invoice_id': invoiceId.trim(),
      'p_expected_updated_at': expectedUpdatedAt.toUtc().toIso8601String(),
    });
  }

  Future<String> addItem({
    required String invoiceId,
    required DateTime expectedUpdatedAt,
    required String description,
    required String quantity,
    required String unitPrice,
  }) async {
    _assertNonEmpty('invoiceId', invoiceId);
    _assertNonEmpty('description', description);
    _assertPositiveDecimal('quantity', quantity);
    _assertNonNegativeDecimal('unitPrice', unitPrice);

    final result = await invokeRpc('add_invoice_item', {
      'p_invoice_id': invoiceId.trim(),
      'p_expected_updated_at': expectedUpdatedAt.toUtc().toIso8601String(),
      'p_description': description.trim(),
      'p_quantity': quantity,
      'p_unit_price': unitPrice,
    });

    final itemId = result.data?['item_id']?.toString() ?? result.data?.toString();
    if (itemId == null || itemId.isEmpty) {
      throw StateError('Add invoice item returned an unexpected shape.');
    }
    return itemId;
  }

  Future<void> updateItem({
    required String itemId,
    required DateTime expectedUpdatedAt,
    required String description,
    required String quantity,
    required String unitPrice,
  }) async {
    _assertNonEmpty('itemId', itemId);
    _assertNonEmpty('description', description);
    _assertPositiveDecimal('quantity', quantity);
    _assertNonNegativeDecimal('unitPrice', unitPrice);

    await invokeRpc('update_invoice_item', {
      'p_item_id': itemId.trim(),
      'p_expected_updated_at': expectedUpdatedAt.toUtc().toIso8601String(),
      'p_description': description.trim(),
      'p_quantity': quantity,
      'p_unit_price': unitPrice,
    });
  }

  Future<void> removeItem({required String itemId, required DateTime expectedUpdatedAt}) async {
    _assertNonEmpty('itemId', itemId);

    await invokeRpc('remove_invoice_item', {
      'p_item_id': itemId.trim(),
      'p_expected_updated_at': expectedUpdatedAt.toUtc().toIso8601String(),
    });
  }

  Future<String> issue({required String invoiceId, required DateTime expectedUpdatedAt}) async {
    _assertNonEmpty('invoiceId', invoiceId);

    final result = await invokeRpc('issue_invoice', {
      'p_invoice_id': invoiceId.trim(),
      'p_expected_updated_at': expectedUpdatedAt.toUtc().toIso8601String(),
    });

    final invoiceNumber = result.data?['invoice_number']?.toString() ?? result.data?.toString();
    if (invoiceNumber == null || invoiceNumber.isEmpty) {
      throw StateError('Issue invoice returned an unexpected shape.');
    }
    return invoiceNumber;
  }

  Future<void> applyLineDiscount({
    required String itemId,
    required DateTime expectedUpdatedAt,
    DiscountKind? kind,
    String? value,
  }) async {
    _assertNonEmpty('itemId', itemId);

    await invokeRpc('apply_line_discount', {
      'p_item_id': itemId.trim(),
      'p_expected_updated_at': expectedUpdatedAt.toUtc().toIso8601String(),
      'p_kind': kind?.wireValue,
      'p_value': value,
    });
  }

  Future<void> applyInvoiceDiscount({
    required String invoiceId,
    required DateTime expectedUpdatedAt,
    DiscountKind? kind,
    String? value,
  }) async {
    _assertNonEmpty('invoiceId', invoiceId);

    await invokeRpc('apply_invoice_discount', {
      'p_invoice_id': invoiceId.trim(),
      'p_expected_updated_at': expectedUpdatedAt.toUtc().toIso8601String(),
      'p_kind': kind?.wireValue,
      'p_value': value,
    });
  }

  Future<void> setInsuranceCoverage({
    required String invoiceId,
    required DateTime expectedUpdatedAt,
    String? providerId,
    required String coveredAmount,
  }) async {
    _assertNonEmpty('invoiceId', invoiceId);

    await invokeRpc('set_insurance_coverage', {
      'p_invoice_id': invoiceId.trim(),
      'p_expected_updated_at': expectedUpdatedAt.toUtc().toIso8601String(),
      'p_provider_id': providerId,
      'p_covered_amount': coveredAmount,
    });
  }

  Future<void> voidInvoice({required String invoiceId, required String reason}) async {
    _assertNonEmpty('invoiceId', invoiceId);
    _assertNonEmpty('reason', reason);

    await invokeRpc('void_invoice', {'p_invoice_id': invoiceId.trim(), 'p_reason': reason.trim()});
  }

  Future<InvoiceDetail> getDetail({required String invoiceId}) async {
    _assertNonEmpty('invoiceId', invoiceId);

    final result = await invokeRpc('get_invoice_detail', {'p_invoice_id': invoiceId.trim()});
    final detail = InvoiceDetail.fromRpcData(result.data);
    if (detail == null) {
      throw StateError('Get invoice detail returned an unexpected shape.');
    }
    return detail;
  }

  Future<List<InvoiceListItem>> listInvoices({Map<String, dynamic>? filters, int limit = 50, int offset = 0}) async {
    final result = await invokeRpc('list_invoices', {
      'p_filters': filters ?? const {},
      'p_limit': limit,
      'p_offset': offset,
    });

    return _parseListRows(result.data);
  }

  Future<InvoiceListItem?> findForVisit({required String visitId}) async {
    final items = await listInvoices(filters: {'visit_id': visitId}, limit: 1);
    if (items.isEmpty) {
      return null;
    }
    return items.first;
  }

  Future<List<InvoiceListItem>> listPatientInvoices({required String patientId, int limit = 50, int offset = 0}) async {
    _assertNonEmpty('patientId', patientId);

    final result = await invokeRpc('list_patient_invoices', {
      'p_patient_id': patientId.trim(),
      'p_limit': limit,
      'p_offset': offset,
    });

    return _parseListRows(result.data);
  }

  List<InvoiceListItem> _parseListRows(Map<String, dynamic>? data) {
    final rawItems = data?['items'] ?? data?['rows'];
    if (rawItems is! List) {
      return const [];
    }

    return [
      for (final item in rawItems)
        if (item is Map<String, dynamic>)
          InvoiceListItem.fromRow(item)
        else if (item is Map)
          InvoiceListItem.fromRow(Map<String, dynamic>.from(item)),
    ].whereType<InvoiceListItem>().toList(growable: false);
  }

  void _assertNonEmpty(String field, String value) {
    if (value.trim().isEmpty) {
      throw RpcFailure(RpcResult(success: false, errorCode: 'INVALID_INPUT', errorMessage: '$field is required.'));
    }
  }

  void _assertPositiveDecimal(String field, String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      throw RpcFailure(RpcResult(success: false, errorCode: 'INVALID_INPUT', errorMessage: '$field is required.'));
    }
    final parsed = double.tryParse(trimmed);
    if (parsed == null || parsed <= 0) {
      throw RpcFailure(
        RpcResult(success: false, errorCode: 'INVALID_INPUT', errorMessage: 'Quantity must be greater than zero.'),
      );
    }
  }

  void _assertNonNegativeDecimal(String field, String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      throw RpcFailure(RpcResult(success: false, errorCode: 'INVALID_INPUT', errorMessage: '$field is required.'));
    }
    final parsed = double.tryParse(trimmed);
    if (parsed == null || parsed < 0) {
      throw RpcFailure(
        RpcResult(success: false, errorCode: 'INVALID_INPUT', errorMessage: 'Unit price cannot be negative.'),
      );
    }
  }
}

final invoiceRepositoryProvider = Provider<InvoiceRepository>((ref) {
  return InvoiceRepository(ref.watch(supabaseClientProvider));
});
