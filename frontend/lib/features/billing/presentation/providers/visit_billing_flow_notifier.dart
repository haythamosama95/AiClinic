import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/features/service_catalog/domain/eligible_service.dart';
import 'package:ai_clinic/features/billing/domain/visit_billing_models.dart';

@immutable
class VisitBillingFlowState {
  const VisitBillingFlowState({
    this.step = VisitBillingStep.services,
    this.selectedLines = const [],
    this.discountType = VisitBillingDiscountType.none,
    this.discountValue = 0,
    this.invoicePreviewNumber,
    this.isSubmitting = false,
  });

  final VisitBillingStep step;
  final List<VisitSelectedServiceLine> selectedLines;
  final VisitBillingDiscountType discountType;
  final double discountValue;
  final String? invoicePreviewNumber;
  final bool isSubmitting;

  VisitBillingTotals get totals => computeVisitBillingTotals(selectedLines, discountType, discountValue);

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
    double? discountValue,
    String? invoicePreviewNumber,
    bool? isSubmitting,
    bool clearInvoicePreviewNumber = false,
  }) {
    return VisitBillingFlowState(
      step: step ?? this.step,
      selectedLines: selectedLines ?? this.selectedLines,
      discountType: discountType ?? this.discountType,
      discountValue: discountValue ?? this.discountValue,
      invoicePreviewNumber: clearInvoicePreviewNumber ? null : (invoicePreviewNumber ?? this.invoicePreviewNumber),
      isSubmitting: isSubmitting ?? this.isSubmitting,
    );
  }
}

/// Local billing workflow state for the post-review visit flow.
final visitBillingFlowProvider = NotifierProvider.autoDispose
    .family<VisitBillingFlowNotifier, VisitBillingFlowState, String>(VisitBillingFlowNotifier.new);

class VisitBillingFlowNotifier extends Notifier<VisitBillingFlowState> {
  VisitBillingFlowNotifier(this._visitId);

  // ignore: unused_field — reserved for visit-scoped side effects.
  final String _visitId;

  @override
  VisitBillingFlowState build() => const VisitBillingFlowState();

  void reset() {
    state = const VisitBillingFlowState();
  }

  void beginBilling() {
    state = VisitBillingFlowState(invoicePreviewNumber: generateVisitBillingInvoicePreviewNumber());
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
        selectedLines: [...state.selectedLines, VisitSelectedServiceLine.fromEligibleService(service)],
      );
      return;
    }

    state = state.copyWith(
      selectedLines: state.selectedLines.where((line) => line.serviceId != service.serviceId).toList(),
    );
  }

  void updateQuantity(String serviceId, int quantity) {
    final nextQuantity = quantity.clamp(1, 99);
    state = state.copyWith(
      selectedLines: [
        for (final line in state.selectedLines)
          if (line.serviceId == serviceId) line.copyWith(quantity: nextQuantity) else line,
      ],
    );
  }

  void setDiscountType(VisitBillingDiscountType type) {
    state = state.copyWith(discountType: type, discountValue: 0);
  }

  void setDiscountValue(double value) {
    state = state.copyWith(discountValue: value);
  }

  void setSubmitting(bool submitting) {
    state = state.copyWith(isSubmitting: submitting);
  }
}
