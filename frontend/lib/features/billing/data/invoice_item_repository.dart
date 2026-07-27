import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ai_clinic/core/config/supabase_config.dart' show supabaseClientProvider;
import 'package:ai_clinic/core/rpc/app_rpc_invoker.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';

/// Result of adding a catalog service to a draft invoice.
class AddInvoiceItemFromServiceResult {
  const AddInvoiceItemFromServiceResult({
    required this.itemId,
    required this.quantity,
    required this.unitPrice,
    required this.appliedRule,
  });

  final String itemId;
  final String quantity;
  final String unitPrice;
  final String appliedRule;
}

/// Invoice line-item RPC wrappers (V1-6 / service-catalog billing integration).
class InvoiceItemRepository with AppRpcInvoker {
  InvoiceItemRepository(this._client);

  final SupabaseClient _client;

  @override
  SupabaseClient get rpcClient => _client;

  @override
  String get migrationHint => '20260712091500_service_catalog_billing_integration.sql';

  @override
  String get rpcLogDomain => 'billing.invoice_items';

  Future<AddInvoiceItemFromServiceResult> addFromService({
    required String invoiceId,
    required DateTime expectedUpdatedAt,
    required String serviceId,
  }) async {
    _assertNonEmpty('invoiceId', invoiceId);
    _assertNonEmpty('serviceId', serviceId);

    final result = await invokeRpc('add_invoice_item_from_service', {
      'p_invoice_id': invoiceId.trim(),
      'p_expected_updated_at': expectedUpdatedAt.toUtc().toIso8601String(),
      'p_service_id': serviceId.trim(),
    });

    final itemId = result.data?['item_id']?.toString();
    final quantity = result.data?['quantity']?.toString();
    final unitPrice = result.data?['unit_price']?.toString();
    final appliedRule = result.data?['applied_rule']?.toString();
    if (itemId == null || itemId.isEmpty || quantity == null || unitPrice == null || appliedRule == null) {
      throw StateError('add_invoice_item_from_service returned an unexpected shape.');
    }

    return AddInvoiceItemFromServiceResult(
      itemId: itemId,
      quantity: quantity,
      unitPrice: unitPrice,
      appliedRule: appliedRule,
    );
  }

  void _assertNonEmpty(String field, String value) {
    if (value.trim().isEmpty) {
      throw RpcFailure(RpcResult(success: false, errorCode: 'INVALID_INPUT', errorMessage: '$field is required.'));
    }
  }
}

final invoiceItemRepositoryProvider = Provider<InvoiceItemRepository>((ref) {
  return InvoiceItemRepository(ref.watch(supabaseClientProvider));
});
