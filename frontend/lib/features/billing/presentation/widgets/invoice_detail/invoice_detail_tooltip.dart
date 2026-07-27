import 'package:flutter/material.dart';

import 'package:ai_clinic/features/billing/domain/invoice_status.dart';

/// Wraps invoice detail actions with a hover tooltip.
class InvoiceDetailTooltip extends StatelessWidget {
  const InvoiceDetailTooltip({required this.message, required this.child, super.key});

  final String message;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Tooltip(message: message, child: child);
  }
}

/// Enabled and disabled tooltip copy for invoice detail actions.
abstract final class InvoiceDetailActionTooltips {
  static String voidMessage({required String? disabledReason}) {
    return disabledReason ?? 'Void this invoice';
  }

  static String? voidDisabledReason({required bool canVoid, required InvoiceStatus status}) {
    if (!canVoid) {
      return 'You do not have permission to void invoices.';
    }
    if (status.isVoided) {
      return 'This invoice has already been voided.';
    }
    if (status.isDraft) {
      return 'Draft invoices cannot be voided.';
    }
    if (status == InvoiceStatus.paid) {
      return 'Paid invoices cannot be voided.';
    }
    if (!status.isVoidable) {
      return 'This invoice cannot be voided in its current state.';
    }
    return null;
  }

  static const printMessage = 'Print invoice receipt';

  static String editMessage({required String? disabledReason}) {
    return disabledReason ?? 'Edit invoice line items and totals';
  }

  static String? editDisabledReason({required bool canCreate, required InvoiceStatus status}) {
    if (!canCreate) {
      return 'You do not have permission to edit invoices.';
    }
    if (!status.isDraft) {
      return 'Only draft invoices can be edited.';
    }
    return null;
  }

  static String addPaymentMessage({required String? disabledReason}) {
    return disabledReason ?? 'Record a payment against this invoice';
  }

  static String? addPaymentDisabledReason({required bool canRecordPayment, required InvoiceStatus status}) {
    if (!canRecordPayment) {
      return 'You do not have permission to record payments.';
    }
    if (status.isDraft) {
      return 'Issue this invoice before recording a payment.';
    }
    if (status.isVoided) {
      return 'Payments cannot be recorded on voided invoices.';
    }
    if (status == InvoiceStatus.paid) {
      return 'This invoice is fully paid.';
    }
    if (status.isTerminal) {
      return 'Payments cannot be recorded on this invoice.';
    }
    return null;
  }

  static String refundMessage({String? disabledReason}) {
    return disabledReason ?? 'Record a refund against this invoice';
  }

  static String? refundDisabledReason({
    required bool canRefund,
    required InvoiceStatus status,
    bool hasPayments = true,
  }) {
    if (!canRefund) {
      return 'You do not have permission to record refunds.';
    }
    if (status.isDraft) {
      return 'Issue this invoice before recording a refund.';
    }
    if (status.isVoided) {
      return 'Refunds cannot be recorded on voided invoices.';
    }
    if (!hasPayments) {
      return 'No payments have been recorded on this invoice.';
    }
    return null;
  }
}
