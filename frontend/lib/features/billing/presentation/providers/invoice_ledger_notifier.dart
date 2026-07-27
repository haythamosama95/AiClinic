import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/billing/data/invoice_repository.dart';
import 'package:ai_clinic/features/billing/data/payment_repository.dart';
import 'package:ai_clinic/features/billing/domain/invoice_stale_exception.dart';
import 'package:ai_clinic/features/billing/domain/payment_method.dart';
import 'package:ai_clinic/features/billing/presentation/providers/invoice_detail_provider.dart';
import 'package:ai_clinic/features/billing/presentation/providers/invoice_list_notifier.dart';

/// Ledger mutations (void, payment, refund) with refresh-after-mutate (V1-6).
final invoiceLedgerProvider = Provider.autoDispose.family<InvoiceLedgerNotifier, String>((ref, invoiceId) {
  return InvoiceLedgerNotifier(ref, invoiceId);
});

class InvoiceLedgerNotifier {
  InvoiceLedgerNotifier(this._ref, this._invoiceId);

  final Ref _ref;
  final String _invoiceId;

  bool _inFlight = false;

  InvoiceRepository get _invoiceRepo => _ref.read(invoiceRepositoryProvider);

  PaymentRepository get _paymentRepo => _ref.read(paymentRepositoryProvider);

  Future<void> voidInvoice({required String reason}) async {
    if (_inFlight) {
      return;
    }

    _inFlight = true;
    try {
      final detail = await _invoiceRepo.getDetail(invoiceId: _invoiceId);
      await _runMutation(() async {
        await _invoiceRepo.voidInvoice(
          invoiceId: _invoiceId,
          expectedUpdatedAt: detail.updatedAt,
          reason: reason,
        );
      });
      await _refreshSurfaces(invoiceId: _invoiceId, patientId: detail.patientId);
    } finally {
      _inFlight = false;
    }
  }

  Future<String> recordPayment({
    required PaymentMethod method,
    required String amount,
    String? reference,
    String? note,
  }) async {
    if (_inFlight) {
      throw StateError('A billing mutation is already in progress.');
    }

    _inFlight = true;
    try {
      final detail = await _invoiceRepo.getDetail(invoiceId: _invoiceId);
      final paymentId = await _runMutation(() async {
        return _paymentRepo.recordPayment(
          invoiceId: _invoiceId,
          method: method,
          amount: amount,
          reference: reference,
          note: note,
        );
      });
      await _refreshSurfaces(invoiceId: _invoiceId, patientId: detail.patientId);
      return paymentId;
    } finally {
      _inFlight = false;
    }
  }

  Future<String> recordRefund({
    required PaymentMethod method,
    required String amount,
    required String note,
  }) async {
    if (_inFlight) {
      throw StateError('A billing mutation is already in progress.');
    }

    _inFlight = true;
    try {
      final detail = await _invoiceRepo.getDetail(invoiceId: _invoiceId);
      final paymentId = await _runMutation(() async {
        return _paymentRepo.recordRefund(
          invoiceId: _invoiceId,
          method: method,
          amount: amount,
          note: note,
        );
      });
      await _refreshSurfaces(invoiceId: _invoiceId, patientId: detail.patientId);
      return paymentId;
    } finally {
      _inFlight = false;
    }
  }

  Future<void> refreshSurfaces() async {
    final detail = await _invoiceRepo.getDetail(invoiceId: _invoiceId);
    await _refreshSurfaces(invoiceId: _invoiceId, patientId: detail.patientId);
  }

  Future<void> _refreshSurfaces({required String invoiceId, required String patientId}) async {
    _ref.invalidate(invoiceDetailViewProvider(invoiceId));
    _ref.invalidate(patientInvoicesProvider(patientId));
    _ref.invalidate(invoiceListProvider);

    await Future.wait([
      _ref.read(invoiceDetailViewProvider(invoiceId).future),
      _ref.read(patientInvoicesProvider(patientId).future),
      _ref.read(invoiceListProvider.notifier).reload(),
    ]);
  }

  Future<T> _runMutation<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on RpcFailure catch (error) {
      if (error.code == 'STALE_INVOICE') {
        throw const InvoiceStaleException();
      }
      rethrow;
    }
  }
}
