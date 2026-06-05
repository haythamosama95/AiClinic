import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/features/billing/data/invoice_repository.dart';
import 'package:ai_clinic/features/billing/domain/invoice_detail.dart';

final invoiceDetailProvider = FutureProvider.autoDispose.family<InvoiceDetail, String>((ref, invoiceId) async {
  return ref.watch(invoiceRepositoryProvider).getDetail(invoiceId: invoiceId);
});
