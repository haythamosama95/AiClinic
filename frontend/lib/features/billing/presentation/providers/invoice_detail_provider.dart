import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/features/billing/data/invoice_repository.dart';
import 'package:ai_clinic/features/billing/domain/invoice_detail.dart';
import 'package:ai_clinic/features/billing/domain/invoice_list_item.dart';
import 'package:ai_clinic/features/billing/domain/invoice_status.dart';

/// Permission-aware invoice detail for billing screens (V1-6).
@immutable
class InvoiceDetailViewState {
  const InvoiceDetailViewState({
    required this.invoice,
    required this.canCreate,
    required this.canApplyDiscount,
    required this.canVoid,
    required this.canRecordPayment,
    required this.canRefund,
  });

  final InvoiceDetail invoice;
  final bool canCreate;
  final bool canApplyDiscount;
  final bool canVoid;
  final bool canRecordPayment;
  final bool canRefund;
}

/// Backend-first invoice detail with permission flags.
final invoiceDetailViewProvider = FutureProvider.autoDispose
    .family<InvoiceDetailViewState, String>((ref, invoiceId) async {
      final id = invoiceId.trim();
      if (id.isEmpty) {
        throw StateError('Invoice id is required.');
      }

      final invoice = await ref
          .read(invoiceRepositoryProvider)
          .getDetail(invoiceId: id);
      final permissions = ref.watch(permissionServiceProvider);

      return InvoiceDetailViewState(
        invoice: invoice,
        canCreate: permissions.canCreateInvoices(),
        canApplyDiscount: permissions.canApplyDiscount(),
        canVoid: permissions.canVoidInvoice(),
        canRecordPayment: permissions.canRecordPayment(),
        canRefund: permissions.canRefundPayment(),
      );
    });

/// Patient invoice history for the patient profile billing section.
final patientInvoicesProvider = FutureProvider.autoDispose
    .family<InvoiceListPageResult, String>((ref, patientId) async {
      final auth = ref.watch(authSessionProvider);
      if (!AuthRouteGuard.canAccessInvoiceList(auth)) {
        return const InvoiceListPageResult(items: [], hasMore: false);
      }

      final repo = ref.read(invoiceRepositoryProvider);
      final page = await repo.listPatientInvoices(patientId: patientId);
      final enrichedItems = await Future.wait(
        page.items.map((item) => _enrichInvoicePayments(repo, item)),
      );

      return InvoiceListPageResult(items: enrichedItems, hasMore: page.hasMore);
    });

Future<InvoiceListItem> _enrichInvoicePayments(
  InvoiceRepository repo,
  InvoiceListItem item,
) async {
  if (item.payments.isNotEmpty || item.status == InvoiceStatus.draft) {
    return item;
  }

  final needsPayments =
      !item.paidAmount.isZero || !item.insuranceCoveredAmount.isZero;
  if (!needsPayments) {
    return item;
  }

  try {
    final detail = await repo.getDetail(invoiceId: item.id);
    if (detail.payments.isEmpty) {
      return item;
    }
    return item.copyWith(payments: detail.payments);
  } on Object {
    return item;
  }
}
