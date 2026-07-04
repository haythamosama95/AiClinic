import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/features/billing/domain/invoice_detail.dart';
import 'package:ai_clinic/features/billing/domain/invoice_item.dart';
import 'package:ai_clinic/features/billing/domain/invoice_status.dart';
import 'package:ai_clinic/features/billing/domain/payment.dart';
import 'package:ai_clinic/features/billing/presentation/utils/billing_formatting.dart';

/// Client-side invoice receipt PDF generation and print pipeline (V1-6 US7).
abstract final class ReceiptPrintPreview {
  static String? watermarkLabel(InvoiceDetail detail) {
    return switch (detail.status) {
      InvoiceStatus.draft => 'DRAFT — NOT FOR PATIENT',
      InvoiceStatus.voided =>
        detail.voidReason == null ? 'VOIDED' : 'VOIDED\n${detail.voidReason}',
      _ => null,
    };
  }

  static Future<void> printInvoice(
    InvoiceDetail detail, {
    String? organizationName,
  }) {
    return Printing.layoutPdf(
      onLayout: (format) => buildReceiptPdf(
        detail,
        format,
        organizationName: organizationName,
      ),
    );
  }

  static Future<void> openPdfPreview(
    InvoiceDetail detail, {
    String? organizationName,
  }) async {
    final bytes = await buildReceiptPdf(
      detail,
      PdfPageFormat.a4,
      organizationName: organizationName,
    );
    final dir = await getTemporaryDirectory();
    final number = detail.invoiceNumber ?? detail.id.substring(0, 8);
    final file = File('${dir.path}/receipt-$number.pdf');
    await file.writeAsBytes(bytes, flush: true);
    await OpenFilex.open(file.path);
  }

  static Future<Uint8List> buildReceiptPdf(
    InvoiceDetail detail,
    PdfPageFormat format, {
    String? organizationName,
  }) async {
    final doc = pw.Document();
    final hasLineDiscounts = detail.items.any(_itemHasLineDiscount);
    final invoiceDiscount = detail.discountAmount.asDouble;
    final insuranceCovered = detail.insuranceCoveredAmount.asDouble;
    final totalDue = detail.subtotal.asDouble - invoiceDiscount - insuranceCovered;
    final headerName = organizationName?.trim().isNotEmpty == true
        ? organizationName!.trim()
        : (detail.branchName ?? 'Clinic');

    doc.addPage(
      pw.Page(
        pageFormat: format,
        build: (context) {
          return pw.Stack(
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    headerName,
                    style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
                  ),
                  if (detail.branchName != null) pw.Text('Branch: ${detail.branchName}'),
                  pw.SizedBox(height: 8),
                  pw.Text('Patient: ${detail.patientDisplayName ?? detail.patientId}'),
                  pw.Text(
                    'Invoice: ${BillingFormatting.invoiceDisplayNumber(detail.invoiceNumber, detail.id)}',
                  ),
                  if (detail.issuedAt != null)
                    pw.Text('Issued: ${BillingFormatting.formatDate(detail.issuedAt!)}'),
                  pw.SizedBox(height: 16),
                  pw.Text('Items', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 8),
                  _itemsTable(detail.items, hasLineDiscounts: hasLineDiscounts),
                  pw.SizedBox(height: 12),
                  _totalRow('Subtotal', detail.subtotal.wireValue, detail.currency),
                  if (hasLineDiscounts)
                    pw.Text(
                      'Line discounts are included in subtotal above.',
                      style: const pw.TextStyle(fontSize: 9),
                    ),
                  if (invoiceDiscount > 0)
                    _totalRow('Invoice discount', '-${detail.discountAmount.wireValue}', detail.currency),
                  if (insuranceCovered > 0)
                    _totalRow(
                      'Insurance covered',
                      detail.insuranceCoveredAmount.wireValue,
                      detail.currency,
                    ),
                  _totalRow('Total due', totalDue.toStringAsFixed(2), detail.currency, emphasized: true),
                  pw.SizedBox(height: 12),
                  pw.Text('Payments', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 8),
                  if (detail.payments.isEmpty)
                    pw.Text('No payments recorded.')
                  else
                    ...detail.payments.map(_paymentRow),
                  pw.SizedBox(height: 8),
                  _totalRow('Balance', detail.balance.wireValue, detail.currency, emphasized: true),
                  if (detail.status == InvoiceStatus.voided && detail.voidReason != null) ...[
                    pw.SizedBox(height: 12),
                    pw.Text('Void reason: ${detail.voidReason}'),
                  ],
                ],
              ),
              if (watermarkLabel(detail) != null) _watermark(watermarkLabel(detail)!),
            ],
          );
        },
      ),
    );

    return doc.save();
  }

  static pw.Widget _itemsTable(List<InvoiceItem> items, {required bool hasLineDiscounts}) {
    final headers = hasLineDiscounts
        ? ['Description', 'Qty', 'Unit', 'Line', 'Discount', 'Total']
        : ['Description', 'Qty', 'Unit price', 'Line total'];

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: headers
              .map(
                (label) => pw.Padding(
                  padding: const pw.EdgeInsets.all(4),
                  child: pw.Text(label),
                ),
              )
              .toList(),
        ),
        ...items.map((item) {
          final cells = hasLineDiscounts
              ? [
                  item.description,
                  item.quantity,
                  item.unitPrice.wireValue,
                  item.lineSubtotal.wireValue,
                  item.lineDiscountAmount.wireValue,
                  item.lineTotal.wireValue,
                ]
              : [
                  item.description,
                  item.quantity,
                  item.unitPrice.wireValue,
                  item.lineTotal.wireValue,
                ];
          return pw.TableRow(
            children: cells
                .map(
                  (value) => pw.Padding(
                    padding: const pw.EdgeInsets.all(4),
                    child: pw.Text(value),
                  ),
                )
                .toList(),
          );
        }),
      ],
    );
  }

  static pw.Widget _totalRow(
    String label,
    String value,
    String currency, {
    bool emphasized = false,
  }) {
    final style = emphasized ? pw.TextStyle(fontWeight: pw.FontWeight.bold) : const pw.TextStyle();
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: style),
          pw.Text('$value $currency', style: style),
        ],
      ),
    );
  }

  static pw.Widget _paymentRow(Payment payment) {
    final label = payment.isRefund ? 'Refund' : 'Payment';
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4),
      child: pw.Text(
        '${BillingFormatting.formatDateTime(payment.recordedAt)} — '
        '${payment.method.label} — $label ${payment.amount.wireValue}',
      ),
    );
  }

  static pw.Widget _watermark(String text) {
    return pw.Positioned.fill(
      child: pw.Center(
        child: pw.Transform.rotate(
          angle: -0.5,
          child: pw.Opacity(
            opacity: 0.18,
            child: pw.Text(
              text,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                fontSize: 36,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.red800,
              ),
            ),
          ),
        ),
      ),
    );
  }

  static bool _itemHasLineDiscount(InvoiceItem item) => !item.lineDiscountAmount.isZero;
}

/// Toolbar actions for printing or opening a receipt PDF.
class ReceiptPrintActions extends StatelessWidget {
  const ReceiptPrintActions({
    required this.detail,
    this.organizationName,
    super.key,
  });

  final InvoiceDetail detail;
  final String? organizationName;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.s2,
      runSpacing: AppSpacing.s2,
      children: [
        AppButton(
          key: const Key('invoice_print_button'),
          label: 'Print receipt',
          size: AppButtonSize.sm,
          variant: AppButtonVariant.secondary,
          leadingIcon: LucideIcons.printer,
          onPressed: () => ReceiptPrintPreview.printInvoice(
            detail,
            organizationName: organizationName,
          ),
        ),
        AppButton(
          key: const Key('invoice_open_pdf_button'),
          label: 'Open PDF',
          size: AppButtonSize.sm,
          variant: AppButtonVariant.ghost,
          leadingIcon: LucideIcons.fileText,
          onPressed: () => ReceiptPrintPreview.openPdfPreview(
            detail,
            organizationName: organizationName,
          ),
        ),
      ],
    );
  }
}
