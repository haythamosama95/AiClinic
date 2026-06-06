import 'package:ai_clinic/features/billing/domain/discount_kind.dart';
import 'package:ai_clinic/features/billing/domain/invoice_detail.dart';
import 'package:ai_clinic/features/billing/domain/invoice_item.dart';
import 'package:ai_clinic/features/billing/domain/invoice_status.dart';
import 'package:ai_clinic/features/billing/domain/payment.dart';
import 'package:ai_clinic/features/billing/domain/payment_method.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/receipt_print_preview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';

InvoiceDetail _sampleDetail({required InvoiceStatus status, List<InvoiceItem>? items, String? voidReason}) {
  final now = DateTime.utc(2026, 6, 2, 11);
  return InvoiceDetail(
    id: 'inv-1',
    invoiceNumber: status == InvoiceStatus.draft ? null : 'INV-MAIN-000001',
    status: status,
    branchId: 'branch-1',
    patientId: 'patient-1',
    visitId: 'visit-1',
    subtotal: '150.00',
    discountKind: DiscountKind.fixed,
    discountValue: '10',
    discountAmount: '10.00',
    insuranceCoveredAmount: '20.00',
    currency: 'USD',
    issuedAt: status == InvoiceStatus.draft ? null : now,
    voidedAt: status == InvoiceStatus.voided ? now : null,
    voidReason: voidReason,
    balance: status == InvoiceStatus.voided ? '0.00' : '120.00',
    updatedAt: now,
    items:
        items ??
        const [
          InvoiceItem(
            id: 'item-1',
            description: 'Consultation',
            quantity: '1',
            unitPrice: '100.00',
            lineSubtotal: '100.00',
            lineDiscountAmount: '0',
            lineTotal: '100.00',
          ),
          InvoiceItem(
            id: 'item-2',
            description: 'Lab work',
            quantity: '1',
            unitPrice: '50.00',
            lineSubtotal: '50.00',
            lineDiscountKind: DiscountKind.percentage,
            lineDiscountValue: '10',
            lineDiscountAmount: '5.00',
            lineTotal: '45.00',
          ),
        ],
    payments: [
      Payment(
        id: 'pay-1',
        method: PaymentMethod.cash,
        amount: '30.00',
        recordedById: 'staff-1',
        recordedByDisplayName: 'Test Staff',
        recordedAt: DateTime.utc(2026, 6, 2, 12),
      ),
    ],
    patientDisplayName: 'Test Patient',
    branchCode: 'MAIN',
    branchName: 'Main Branch',
    insuranceProviderName: 'Acme Insurance',
  );
}

void main() {
  group('ReceiptPrintPreview', () {
    test('draft watermark and required fields are defined', () async {
      final detail = _sampleDetail(status: InvoiceStatus.draft);
      expect(ReceiptPrintPreview.watermarkLabel(detail), 'DRAFT - NOT FOR PATIENT');
      expect(ReceiptPrintPreview.requiredFieldLabels(detail), contains('Patient'));

      final bytes = await ReceiptPrintPreview.buildReceiptPdf(
        detail,
        PdfPageFormat.letter,
        organizationName: 'Demo Clinic',
      );
      expect(bytes.length, greaterThan(500));
    });

    test('voided watermark includes void reason', () async {
      final detail = _sampleDetail(status: InvoiceStatus.voided, voidReason: 'Duplicate charge');
      expect(ReceiptPrintPreview.watermarkLabel(detail), 'VOIDED\nDuplicate charge');
      expect(ReceiptPrintPreview.requiredFieldLabels(detail), contains('Void reason: Duplicate charge'));

      final bytes = await ReceiptPrintPreview.buildReceiptPdf(detail, PdfPageFormat.letter);
      expect(bytes, isNotEmpty);
    });

    test('issued receipt includes invoice discount and insurance lines', () async {
      final detail = _sampleDetail(status: InvoiceStatus.issued);
      final labels = ReceiptPrintPreview.requiredFieldLabels(detail);
      expect(labels, contains('Invoice discount'));
      expect(labels, contains('Insurance covered'));

      final bytes = await ReceiptPrintPreview.buildReceiptPdf(detail, PdfPageFormat.letter);
      expect(bytes, isNotEmpty);
    });

    test('renders within NFR-004 budget for 100 line items', () async {
      final items = List<InvoiceItem>.generate(
        100,
        (index) => InvoiceItem(
          id: 'item-$index',
          description: 'Service $index',
          quantity: '1',
          unitPrice: '10.00',
          lineSubtotal: '10.00',
          lineDiscountAmount: '0',
          lineTotal: '10.00',
        ),
        growable: false,
      );

      final stopwatch = Stopwatch()..start();
      final bytes = await ReceiptPrintPreview.buildReceiptPdf(
        _sampleDetail(status: InvoiceStatus.issued, items: items),
        PdfPageFormat.letter,
      );
      stopwatch.stop();

      expect(bytes, isNotEmpty);
      expect(stopwatch.elapsedMilliseconds, lessThan(2000));
    });
  });
}
