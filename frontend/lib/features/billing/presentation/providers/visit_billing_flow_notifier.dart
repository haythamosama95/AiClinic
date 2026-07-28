import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/features/billing/domain/visit_billing_models.dart';
import 'package:ai_clinic/features/service_catalog/domain/eligible_service.dart';

@immutable
class VisitBillingFlowState {
  VisitBillingFlowState({
    this.step = VisitBillingStep.services,
    this.selectedLines = const [],
    this.discountType = VisitBillingDiscountType.none,
    Decimal? discountValue,
    this.invoicePreviewNumber,
    this.isSubmitting = false,
    this.draftInvoiceId,
  }) : discountValue = discountValue ?? Decimal.zero;

  final VisitBillingStep step;
  final List<VisitSelectedServiceLine> selectedLines;
  final VisitBillingDiscountType discountType;
  final Decimal discountValue;
  final String? invoicePreviewNumber;
  final bool isSubmitting;
  final String? draftInvoiceId;

  VisitBillingTotals get totals =>
      computeVisitBillingTotals(selectedLines, discountType, discountValue);

  VisitBillingInvoicePreview? get invoicePreview {
    final number = invoicePreviewNumber;
    if (number == null) {
      return null;
    }
    final totals = this.totals;
    return VisitBillingInvoicePreview(
      number: number,
      lines: selectedLines,
      discountType: discountType,
      discountValue: discountValue,
      subtotal: totals.subtotal,
      discountAmount: totals.discountAmount,
      total: totals.total,
    );
  }

  VisitBillingFlowState copyWith({
    VisitBillingStep? step,
    List<VisitSelectedServiceLine>? selectedLines,
    VisitBillingDiscountType? discountType,
    Decimal? discountValue,
    String? invoicePreviewNumber,
    bool? isSubmitting,
    String? draftInvoiceId,
    bool clearInvoicePreviewNumber = false,
    bool clearDraftInvoiceId = false,
  }) {
    return VisitBillingFlowState(
      step: step ?? this.step,
      selectedLines: selectedLines ?? this.selectedLines,
      discountType: discountType ?? this.discountType,
      discountValue: discountValue ?? this.discountValue,
      invoicePreviewNumber: clearInvoicePreviewNumber
          ? null
          : (invoicePreviewNumber ?? this.invoicePreviewNumber),
      isSubmitting: isSubmitting ?? this.isSubmitting,
      draftInvoiceId: clearDraftInvoiceId ? null : (draftInvoiceId ?? this.draftInvoiceId),
    );
  }
}

/// Local billing workflow state for the post-review visit flow.
final visitBillingFlowProvider = NotifierProvider.autoDispose
    .family<VisitBillingFlowNotifier, VisitBillingFlowState, String>(
      VisitBillingFlowNotifier.new,
    );

class VisitBillingFlowNotifier extends Notifier<VisitBillingFlowState> {
  VisitBillingFlowNotifier(String _);


  @override
  VisitBillingFlowState build() => VisitBillingFlowState();

  void reset() {
    state = VisitBillingFlowState();
  }

  void beginBilling() {
    state = VisitBillingFlowState(
      invoicePreviewNumber: generateVisitBillingInvoicePreviewNumber(),
    );
  }

  void setStep(VisitBillingStep step) {
    state = state.copyWith(step: step);
  }

  void toggleService(EligibleService service, {required bool selected}) {
    if (selected) {
      if (state.selectedLines.any((line) => line.serviceId == service.serviceId)) {
        return;
      }
      state = state.copyWith(
        selectedLines: [
          ...state.selectedLines,
          VisitSelectedServiceLine.fromEligibleService(service),
        ],
      );
      return;
    }

    state = state.copyWith(
      selectedLines: state.selectedLines
          .where((line) => line.serviceId != service.serviceId)
          .toList(),
    );
  }

  void updateQuantity(String serviceId, int quantity) {
    final nextQuantity = quantity.clamp(1, 99);
    state = state.copyWith(
      selectedLines: [
        for (final line in state.selectedLines)
          if (line.serviceId == serviceId)
            line.copyWith(quantity: nextQuantity)
          else
            line,
      ],
    );
  }

  void setDiscountType(VisitBillingDiscountType type) {
    state = state.copyWith(discountType: type, discountValue: Decimal.zero);
  }

  void setDiscountValue(String raw) {
    state = state.copyWith(
      discountValue: Decimal.tryParse(raw.trim()) ?? Decimal.zero,
    );
  }

  void setSubmitting(bool submitting) {
    state = state.copyWith(isSubmitting: submitting);
  }

  void recordInvoiceFailure({String? draftInvoiceId}) {
    state = state.copyWith(draftInvoiceId: draftInvoiceId);
  }

  void clearDraftInvoice() {
    state = state.copyWith(clearDraftInvoiceId: true);
  }
}
