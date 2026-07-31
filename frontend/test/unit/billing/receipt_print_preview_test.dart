import 'package:ai_clinic/features/billing/domain/invoice_detail.dart';
import 'package:ai_clinic/features/billing/domain/invoice_item.dart';
import 'package:ai_clinic/features/billing/domain/invoice_status.dart';
import 'package:ai_clinic/features/billing/domain/money.dart';
import 'package:ai_clinic/features/billing/domain/payment.dart';
import 'package:ai_clinic/features/billing/domain/payment_method.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/receipt_print_preview.dart';
import 'package:flutter_test/flutter_test.dart';

InvoiceDetail _invoice({String? invoiceNumber, String? patientDisplayName, DateTime? issuedAt, DateTime? createdAt}) {
  return InvoiceDetail(
    id: 'inv-abcdef12',
    invoiceNumber: invoiceNumber,
    status: InvoiceStatus.issued,
    branchId: 'branch-1',
    patientId: 'patient-1',
    visitId: 'visit-1',
    subtotal: Money.parse('100.00'),
    discountAmount: Money.parse('0.00'),
    insuranceCoveredAmount: Money.parse('0.00'),
    currency: 'USD',
    balance: Money.parse('100.00'),
    createdAt: createdAt ?? DateTime.parse('2026-06-01T10:00:00.000Z'),
    updatedAt: DateTime.parse('2026-06-02T12:00:00.000Z'),
    items: const [],
    payments: const [],
    patientDisplayName: patientDisplayName,
    issuedAt: issuedAt,
  );
}

void main() {
  group('ReceiptPrintPreview.pdfFileName', () {
    test('builds descriptive filename from invoice number, patient, and issued date', () {
      final invoice = _invoice(
        invoiceNumber: 'INV-000001',
        patientDisplayName: 'Ahmed Hassan',
        issuedAt: DateTime.parse('2026-06-15T08:30:00.000Z'),
      );

      expect(ReceiptPrintPreview.pdfFileName(invoice), 'aiclinc-invoice-inv-000001-ahmed-hassan-2026-06-15.pdf');
    });

    test('falls back to invoice id prefix and createdAt when number and issuedAt are missing', () {
      final invoice = _invoice(
        invoiceNumber: null,
        patientDisplayName: 'Jane Doe',
        createdAt: DateTime.parse('2026-01-20T10:00:00.000Z'),
      );

      expect(ReceiptPrintPreview.pdfFileName(invoice), 'aiclinc-invoice-inv-abcd-jane-doe-2026-01-20.pdf');
    });

    test('sanitizes special characters in patient name', () {
      final invoice = _invoice(
        invoiceNumber: 'INV-9',
        patientDisplayName: 'O\'Connor / Smith',
        issuedAt: DateTime.parse('2026-03-01T00:00:00.000Z'),
      );

      expect(ReceiptPrintPreview.pdfFileName(invoice), 'aiclinc-invoice-inv-9-o-connor-smith-2026-03-01.pdf');
    });
  });

  group('ReceiptPrintPreview.buildDocument', () {
    test('builds a non-empty PDF for a typical issued invoice', () async {
      final invoice =
          _invoice(
            invoiceNumber: 'INV-000001',
            patientDisplayName: 'Ahmed Hassan',
            issuedAt: DateTime.parse('2026-06-15T08:30:00.000Z'),
          ).copyWith(
            branchName: 'Main Clinic',
            branchCode: 'MC-01',
            patientMrn: 'MRN-12345',
            patientPhone: '+20 100 234 5678',
            items: [
              InvoiceItem(
                id: 'item-1',
                description: 'Consultation',
                quantity: '1',
                unitPrice: Money.parse('100.00'),
                lineSubtotal: Money.parse('100.00'),
                lineDiscountAmount: Money.parse('0.00'),
                lineTotal: Money.parse('100.00'),
              ),
            ],
            payments: [
              Payment(
                id: 'pay-1',
                amount: Money.parse('50.00'),
                method: PaymentMethod.cash,
                recordedById: 'user-1',
                recordedAt: DateTime.parse('2026-06-15T10:00:00.000Z'),
              ),
            ],
          );

      final doc = await ReceiptPrintPreview.buildDocument(invoice);
      final bytes = await doc.save();

      expect(bytes, isNotEmpty);
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    });
  });
}

extension on InvoiceDetail {
  InvoiceDetail copyWith({
    String? branchName,
    String? branchCode,
    String? patientMrn,
    String? patientPhone,
    List<InvoiceItem>? items,
    List<Payment>? payments,
  }) {
    return InvoiceDetail(
      id: id,
      invoiceNumber: invoiceNumber,
      status: status,
      branchId: branchId,
      patientId: patientId,
      visitId: visitId,
      subtotal: subtotal,
      discountAmount: discountAmount,
      insuranceCoveredAmount: insuranceCoveredAmount,
      currency: currency,
      balance: balance,
      createdAt: createdAt,
      updatedAt: updatedAt,
      items: items ?? this.items,
      payments: payments ?? this.payments,
      patientDisplayName: patientDisplayName,
      issuedAt: issuedAt,
      branchName: branchName ?? this.branchName,
      branchCode: branchCode ?? this.branchCode,
      patientMrn: patientMrn ?? this.patientMrn,
      patientPhone: patientPhone ?? this.patientPhone,
    );
  }
}
