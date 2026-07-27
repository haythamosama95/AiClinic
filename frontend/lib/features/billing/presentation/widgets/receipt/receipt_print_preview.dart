import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import 'package:ai_clinic/features/billing/domain/invoice_detail.dart';
import 'package:ai_clinic/features/billing/presentation/utils/billing_formatting.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/receipt/receipt_pdf_document.dart';

/// Builds a printable receipt PDF and opens the OS print dialog (V1-6 US7).
abstract final class ReceiptPrintPreview {
  static Future<void> show(BuildContext context, InvoiceDetail invoice) async {
    final bytes = await (await ReceiptPdfDocument.build(invoice)).save();
    if (!context.mounted) {
      return;
    }

    await Printing.layoutPdf(name: pdfFileName(invoice), onLayout: (_) async => bytes);
  }

  static String pdfFileName(InvoiceDetail invoice) {
    final label = BillingFormatting.invoiceDisplayNumber(invoice.invoiceNumber, invoice.id);
    final sanitized = label.replaceAll(RegExp(r'[^\w\-]+'), '-').replaceAll(RegExp(r'-+'), '-').toLowerCase();
    return 'receipt-$sanitized.pdf';
  }
}
