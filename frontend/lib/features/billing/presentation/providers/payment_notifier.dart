import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/features/billing/data/payment_repository.dart';
import 'package:ai_clinic/features/billing/domain/payment_method.dart';

/// Records payments and refunds against an invoice (V1-6 US2).
class PaymentNotifier {
  PaymentNotifier(this._ref);

  final Ref _ref;

  PaymentRepository get _repo => _ref.read(paymentRepositoryProvider);

  Future<String> recordPayment({
    required String invoiceId,
    required PaymentMethod method,
    required String amount,
    String? note,
  }) {
    return _repo.recordPayment(invoiceId: invoiceId, method: method, amount: amount, note: note);
  }

  Future<String> recordRefund({
    required String invoiceId,
    required PaymentMethod method,
    required String amount,
    required String note,
  }) {
    return _repo.recordRefund(invoiceId: invoiceId, method: method, amount: amount, note: note);
  }
}

final paymentNotifierProvider = Provider<PaymentNotifier>((ref) => PaymentNotifier(ref));
