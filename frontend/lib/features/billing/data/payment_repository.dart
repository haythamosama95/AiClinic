import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ai_clinic/core/config/supabase_config.dart' show supabaseClientProvider;
import 'package:ai_clinic/core/rpc/app_rpc_invoker.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/billing/domain/payment_method.dart';

/// Payment and refund RPC wrappers (V1-6).
class PaymentRepository with AppRpcInvoker {
  PaymentRepository(this._client);

  final SupabaseClient _client;

  @override
  SupabaseClient get rpcClient => _client;

  @override
  String get migrationHint => '20260605180000_billing.sql';

  @override
  String get rpcLogDomain => 'billing.payments';

  Future<String> recordPayment({
    required String invoiceId,
    required PaymentMethod method,
    required String amount,
    String? reference,
    String? note,
  }) async {
    _assertNonEmpty('invoiceId', invoiceId);
    final trimmedAmount = _assertPositiveDecimal('amount', amount);

    final result = await invokeRpc('record_payment', {
      'p_invoice_id': invoiceId.trim(),
      'p_method': method.wireValue,
      'p_amount': trimmedAmount,
      'p_reference': reference,
      'p_note': note,
    });

    final paymentId = result.data?['payment_id']?.toString() ?? result.data?.toString();
    if (paymentId == null || paymentId.isEmpty) {
      throw StateError('Record payment returned an unexpected shape.');
    }
    return paymentId;
  }

  Future<String> recordRefund({
    required String invoiceId,
    required PaymentMethod method,
    required String amount,
    required String note,
  }) async {
    _assertNonEmpty('invoiceId', invoiceId);
    final trimmedAmount = _assertPositiveDecimal('amount', amount);
    _assertNonEmpty('note', note);

    final result = await invokeRpc('record_refund', {
      'p_invoice_id': invoiceId.trim(),
      'p_method': method.wireValue,
      'p_amount': trimmedAmount,
      'p_note': note.trim(),
    });

    final paymentId = result.data?['payment_id']?.toString() ?? result.data?.toString();
    if (paymentId == null || paymentId.isEmpty) {
      throw StateError('Record refund returned an unexpected shape.');
    }
    return paymentId;
  }

  void _assertNonEmpty(String field, String value) {
    if (value.trim().isEmpty) {
      throw RpcFailure(RpcResult(success: false, errorCode: 'INVALID_INPUT', errorMessage: '$field is required.'));
    }
  }

  String _assertPositiveDecimal(String field, String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      throw RpcFailure(RpcResult(success: false, errorCode: 'INVALID_INPUT', errorMessage: '$field is required.'));
    }
    final parsed = double.tryParse(trimmed);
    if (parsed == null || parsed <= 0) {
      throw RpcFailure(
        RpcResult(success: false, errorCode: 'INVALID_INPUT', errorMessage: 'Amount must be greater than zero.'),
      );
    }
    return trimmed;
  }
}

final paymentRepositoryProvider = Provider<PaymentRepository>((ref) {
  return PaymentRepository(ref.watch(supabaseClientProvider));
});
