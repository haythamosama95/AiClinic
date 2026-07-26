import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'package:ai_clinic/features/billing/domain/invoice_detail.dart';
import 'package:ai_clinic/features/billing/domain/invoice_status.dart';
import 'package:ai_clinic/features/billing/domain/money.dart';
import 'package:ai_clinic/features/billing/presentation/utils/billing_formatting.dart';

/// Builds a printable receipt PDF and opens the OS print dialog (V1-6 US7).
abstract final class ReceiptPrintPreview {
  static Future<void> show(BuildContext context, InvoiceDetail invoice) async {
    final bytes = await (await buildDocument(invoice)).save();
    if (!context.mounted) {
      return;
    }

    await Printing.layoutPdf(name: pdfFileName(invoice), onLayout: (_) async => bytes);
  }

  static Future<pw.Document> buildDocument(InvoiceDetail invoice) async {
    final doc = pw.Document();
    final currency = invoice.currency;
    final paidTotal = invoice.payments.fold<Money>(Money.zero, (sum, payment) => sum + payment.amount);
    final watermark = switch (invoice.status) {
      InvoiceStatus.draft => 'DRAFT — NOT FOR PATIENT',
      InvoiceStatus.voided => 'VOIDED',
      _ => null,
    };

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
          pw.Table.fromTextArray(
            headers: const ['Description', 'Qty', 'Unit', 'Total'],
            data: [
              for (final item in invoice.items)
                [
                  item.description,
                  item.quantity,
                  BillingFormatting.formatMoney(item.unitPrice, currency: currency),
                  BillingFormatting.formatMoney(item.lineTotal, currency: currency),
                ],
            ],
          ),
          pw.SizedBox(height: 16),
          _pdfRow('Subtotal', BillingFormatting.formatMoney(invoice.subtotal, currency: currency)),
          if (!invoice.discountAmount.isZero)
            _pdfRow('Discount', '-${BillingFormatting.formatMoney(invoice.discountAmount, currency: currency)}'),
          if (!invoice.insuranceCoveredAmount.isZero)
            _pdfRow(
              invoice.insuranceProviderName ?? 'Insurance',
              '-${BillingFormatting.formatMoney(invoice.insuranceCoveredAmount, currency: currency)}',
            ),
          if (!paidTotal.isZero) _pdfRow('Paid', BillingFormatting.formatMoney(paidTotal, currency: currency)),
          _pdfRow('Balance', BillingFormatting.formatMoney(invoice.balance, currency: currency), bold: true),
          if (invoice.payments.isNotEmpty) ...[
            pw.SizedBox(height: 16),
            pw.Text('Payments', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 8),
            pw.Table.fromTextArray(
              headers: const ['Method', 'Amount', 'Date'],
              data: [
                for (final payment in invoice.payments)
                  [
                    payment.method.label,
                    BillingFormatting.formatMoney(payment.amount, currency: currency),
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

  static String pdfFileName(InvoiceDetail invoice) {
    final label = BillingFormatting.invoiceDisplayNumber(invoice.invoiceNumber, invoice.id);
    final sanitized = label.replaceAll(RegExp(r'[^\w\-]+'), '-').replaceAll(RegExp(r'-+'), '-').toLowerCase();
    return 'receipt-$sanitized.pdf';
  }
}
