import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:ai_clinic/features/billing/domain/invoice_detail.dart';
import 'package:ai_clinic/features/billing/domain/invoice_status.dart';
import 'package:ai_clinic/core/money/money_formatter.dart';
import 'package:ai_clinic/features/billing/presentation/utils/billing_formatting.dart';
import 'package:ai_clinic/features/billing/presentation/utils/invoice_labels.dart';

/// PDF layout for invoice receipts (V1-6 US7).
abstract final class ReceiptPdfDocument {
  static Future<pw.Document> build(InvoiceDetail invoice) async {
    final doc = pw.Document();
    final currency = invoice.currency;
    final paidTotal = invoice.netPaid;
    final watermark = switch (invoice.status) {
      InvoiceStatus.draft => 'DRAFT — NOT FOR PATIENT',
      InvoiceStatus.voided => 'VOIDED',
      _ => null,
    };
    final balanceLabel = InvoiceLabels.balanceLabel(isVoided: invoice.status.isVoided);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          if (watermark != null)
            pw.Center(
              child: pw.Text(
                watermark,
                style: pw.TextStyle(fontSize: 36, color: PdfColors.grey300, fontWeight: pw.FontWeight.bold),
              ),
            ),
          pw.SizedBox(height: 12),
          pw.Text('Invoice receipt', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          pw.Text(BillingFormatting.invoiceDisplayNumber(invoice.invoiceNumber, invoice.id)),
          if (invoice.branchName != null) pw.Text('Branch: ${invoice.branchName}'),
          if (invoice.patientDisplayName != null) pw.Text('Patient: ${invoice.patientDisplayName}'),
          if (invoice.issuedAt != null) pw.Text('Issued: ${BillingFormatting.formatDateTime(invoice.issuedAt!)}'),
          if (invoice.status.isVoided && invoice.voidReason != null) pw.Text('Void reason: ${invoice.voidReason}'),
          pw.SizedBox(height: 16),
          pw.TableHelper.fromTextArray(
            headers: const ['Description', 'Qty', 'Unit', 'Total'],
            data: [
              for (final item in invoice.items)
                [
                  item.description,
                  item.quantity,
                  MoneyFormatter.format(item.unitPrice, currency: currency),
                  MoneyFormatter.format(item.lineTotal, currency: currency),
                ],
            ],
          ),
          pw.SizedBox(height: 16),
          _pdfRow('Subtotal', MoneyFormatter.format(invoice.subtotal, currency: currency)),
          if (!invoice.discountAmount.isZero)
            _pdfRow('Discount', '-${MoneyFormatter.format(invoice.discountAmount, currency: currency)}'),
          if (!invoice.insuranceCoveredAmount.isZero)
            _pdfRow(
              invoice.insuranceProviderName ?? 'Insurance',
              '-${MoneyFormatter.format(invoice.insuranceCoveredAmount, currency: currency)}',
            ),
          if (!paidTotal.isZero) _pdfRow('Paid', MoneyFormatter.format(paidTotal, currency: currency)),
          _pdfRow(balanceLabel, MoneyFormatter.format(invoice.balance, currency: currency), bold: true),
          if (invoice.payments.isNotEmpty) ...[
            pw.SizedBox(height: 16),
            pw.Text('Payments', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 8),
            pw.TableHelper.fromTextArray(
              headers: const ['Method', 'Amount', 'Date'],
              data: [
                for (final payment in invoice.payments)
                  [
                    payment.method.label,
                    MoneyFormatter.format(payment.amount, currency: currency),
                    BillingFormatting.formatDateTime(payment.recordedAt),
                  ],
              ],
            ),
          ],
        ],
      ),
    );

    return doc;
  }

  static pw.Widget _pdfRow(String label, String value, {bool bold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: pw.TextStyle(fontWeight: bold ? pw.FontWeight.bold : null)),
          pw.Text(value, style: pw.TextStyle(fontWeight: bold ? pw.FontWeight.bold : null)),
        ],
      ),
    );
  }
}
