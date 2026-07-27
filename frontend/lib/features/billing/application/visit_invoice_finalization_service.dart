import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/money/money.dart';

import 'package:ai_clinic/features/billing/data/invoice_item_repository.dart';
import 'package:ai_clinic/features/billing/data/invoice_repository.dart';
import 'package:ai_clinic/features/billing/domain/discount_kind.dart';
import 'package:ai_clinic/features/billing/domain/invoice_detail.dart';
import 'package:ai_clinic/features/billing/domain/visit_billing_models.dart';

/// Orchestrates draft creation and issuance for post-visit billing.
class VisitInvoiceFinalizationService {
  const VisitInvoiceFinalizationService(this._invoices, this._invoiceItems);

  final InvoiceRepository _invoices;
  final InvoiceItemRepository _invoiceItems;

  /// Reuses an existing draft for [visitId] when present; otherwise creates one.
  Future<String> resolveOrCreateDraft(String visitId, {String? knownDraftId}) async {
    final trimmedKnown = knownDraftId?.trim();
    if (trimmedKnown != null && trimmedKnown.isNotEmpty) {
      return trimmedKnown;
    }

    final existing = await _invoices.findForVisit(visitId: visitId);
    if (existing != null && existing.status.isDraft) {
      return existing.id;
    }

    return _invoices.createFromVisit(visitId: visitId);
  }

  Future<InvoiceDetail> createIssuedInvoiceForVisit({
    required String visitId,
    String? existingDraftId,
    required List<VisitSelectedServiceLine> lines,
    required VisitBillingDiscountType discountType,
    required Decimal discountValue,
    required bool canApplyDiscount,
  }) async {
    final invoiceId = await resolveOrCreateDraft(visitId, knownDraftId: existingDraftId);
    var invoice = await _invoices.getDetail(invoiceId: invoiceId);

    for (final line in lines) {
      final result = await _invoiceItems.addFromService(
        invoiceId: invoice.id,
        expectedUpdatedAt: invoice.updatedAt,
        serviceId: line.serviceId,
      );

      invoice = await _invoices.getDetail(invoiceId: invoiceId);

      if (line.quantity > 1) {
        final item = invoice.items.firstWhere((entry) => entry.id == result.itemId);
        await _invoices.updateItem(
          itemId: result.itemId,
          expectedUpdatedAt: invoice.updatedAt,
          description: item.description,
          quantity: line.quantity.toString(),
          unitPrice: item.unitPrice.wireValue,
        );
        invoice = await _invoices.getDetail(invoiceId: invoiceId);
      }
    }

    if (canApplyDiscount && discountType != VisitBillingDiscountType.none && discountValue > Decimal.zero) {
      final kind = switch (discountType) {
        VisitBillingDiscountType.percentage => DiscountKind.percentage,
        VisitBillingDiscountType.fixed => DiscountKind.fixed,
        VisitBillingDiscountType.none => null,
      };
      if (kind != null) {
        await _invoices.applyInvoiceDiscount(
          invoiceId: invoice.id,
          expectedUpdatedAt: invoice.updatedAt,
          kind: kind,
          value: discountType == VisitBillingDiscountType.percentage
              ? discountValue.toString()
              : Money.parse(discountValue.toString()).wireValue,
        );
        invoice = await _invoices.getDetail(invoiceId: invoiceId);
      }
    }

    await _invoices.issue(invoiceId: invoice.id, expectedUpdatedAt: invoice.updatedAt);
    return _invoices.getDetail(invoiceId: invoiceId);
  }
}

final visitInvoiceFinalizationServiceProvider = Provider<VisitInvoiceFinalizationService>((ref) {
  return VisitInvoiceFinalizationService(
    ref.watch(invoiceRepositoryProvider),
    ref.watch(invoiceItemRepositoryProvider),
  );
});
