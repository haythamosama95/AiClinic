import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/features/billing/domain/invoice_status.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/invoice_detail/invoice_detail_tooltip.dart';

void main() {
  group('InvoiceDetailActionTooltips', () {
    test('editDisabledReason explains missing permission', () {
      expect(
        InvoiceDetailActionTooltips.editDisabledReason(canCreate: false, status: InvoiceStatus.draft),
        'You do not have permission to edit invoices.',
      );
    });

    test('editDisabledReason explains non-draft status', () {
      expect(
        InvoiceDetailActionTooltips.editDisabledReason(canCreate: true, status: InvoiceStatus.issued),
        'Only draft invoices can be edited.',
      );
    });

    test('addPaymentDisabledReason explains draft invoice', () {
      expect(
        InvoiceDetailActionTooltips.addPaymentDisabledReason(canRecordPayment: true, status: InvoiceStatus.draft),
        'Issue this invoice before recording a payment.',
      );
    });

    test('voidDisabledReason explains paid invoice', () {
      expect(
        InvoiceDetailActionTooltips.voidDisabledReason(canVoid: true, status: InvoiceStatus.paid),
        'Paid invoices cannot be voided.',
      );
    });

    test('enabled messages are returned when no disabled reason exists', () {
      expect(InvoiceDetailActionTooltips.editMessage(disabledReason: null), 'Edit invoice line items and totals');
      expect(
        InvoiceDetailActionTooltips.addPaymentMessage(disabledReason: null),
        'Record a payment against this invoice',
      );
      expect(InvoiceDetailActionTooltips.voidMessage(disabledReason: null), 'Void this invoice');
    });
  });
}
