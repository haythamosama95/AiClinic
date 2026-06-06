import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'package:ai_clinic/features/billing/domain/invoice_detail.dart';
import 'package:ai_clinic/features/billing/domain/invoice_item.dart';
import 'package:ai_clinic/features/billing/domain/invoice_status.dart';
import 'package:ai_clinic/features/billing/domain/payment.dart';

typedef ReceiptPrintHandler = Future<void> Function(Future<Uint8List> Function(PdfPageFormat format) layout);

/// Printable invoice receipt (V1-6 US7).
class ReceiptPrintPreview {
  ReceiptPrintPreview._();

  static ReceiptPrintHandler printHandler = (layout) => Printing.layoutPdf(onLayout: layout);

  /// Watermark label rendered for draft/voided receipts (test hook).
  static String? watermarkLabel(InvoiceDetail detail) {
    return switch (detail.status) {
      InvoiceStatus.draft => 'DRAFT - NOT FOR PATIENT',
      InvoiceStatus.voided => detail.voidReason == null ? 'VOIDED' : 'VOIDED\n${detail.voidReason}',
      _ => null,
    };
  }

  /// Required receipt sections for acceptance checks (test hook).
  static List<String> requiredFieldLabels(InvoiceDetail detail) {
    final hasLineDiscounts = detail.items.any(_itemHasLineDiscount);
    final invoiceDiscount = _parseAmount(detail.discountAmount);
    final insuranceCovered = _parseAmount(detail.insuranceCoveredAmount);

    return [
      'Patient',
      'Invoice',
      'Items',
      'Subtotal',
      if (hasLineDiscounts) 'Line discounts are included in subtotal above.',
      if (invoiceDiscount > 0) 'Invoice discount',
      if (insuranceCovered > 0) 'Insurance covered',
      'Total due',
      'Payments',
      'Balance',
      if (detail.status == InvoiceStatus.voided && detail.voidReason != null) 'Void reason: ${detail.voidReason}',
    ];
  }

  static Future<void> printInvoice(InvoiceDetail detail, {String? organizationName}) {
    return printHandler((format) => buildReceiptPdf(detail, format, organizationName: organizationName));
  }

  static Future<Uint8List> buildReceiptPdf(
    InvoiceDetail detail,
    PdfPageFormat format, {
    String? organizationName,
  }) async {
    final doc = pw.Document();
    final hasLineDiscounts = detail.items.any(_itemHasLineDiscount);
    final invoiceDiscount = _parseAmount(detail.discountAmount);
    final insuranceCovered = _parseAmount(detail.insuranceCoveredAmount);
    final totalDue = _parseAmount(detail.subtotal) - invoiceDiscount - insuranceCovered;
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
                  pw.Text(headerName, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
                  if (detail.branchName != null) pw.Text('Branch: ${detail.branchName}'),
                  pw.SizedBox(height: 8),
                  pw.Text('Patient: ${detail.patientDisplayName ?? detail.patientId}'),
                  pw.Text('Invoice: ${detail.invoiceNumber ?? 'Draft'}'),
                  if (detail.issuedAt != null) pw.Text('Issued: ${_formatDate(detail.issuedAt!)}'),
                  pw.SizedBox(height: 16),
                  pw.Text('Items', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 8),
                  _itemsTable(detail.items, hasLineDiscounts: hasLineDiscounts),
                  pw.SizedBox(height: 12),
                  _totalRow('Subtotal', detail.subtotal, detail.currency),
                  if (hasLineDiscounts)
                    pw.Text('Line discounts are included in subtotal above.', style: const pw.TextStyle(fontSize: 9)),
                  if (invoiceDiscount > 0) _totalRow('Invoice discount', '-${detail.discountAmount}', detail.currency),
                  if (insuranceCovered > 0)
                    _totalRow('Insurance covered', detail.insuranceCoveredAmount, detail.currency),
                  _totalRow('Total due', totalDue.toStringAsFixed(2), detail.currency, emphasized: true),
                  pw.SizedBox(height: 12),
                  pw.Text('Payments', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 8),
                  if (detail.payments.isEmpty)
                    pw.Text('No payments recorded.')
                  else
                    ...detail.payments.map(_paymentRow),
                  pw.SizedBox(height: 8),
                  _totalRow('Balance', detail.balance, detail.currency, emphasized: true),
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
      columnWidths: hasLineDiscounts
          ? {
              0: const pw.FlexColumnWidth(3),
              1: const pw.FlexColumnWidth(1),
              2: const pw.FlexColumnWidth(1.2),
              3: const pw.FlexColumnWidth(1.2),
              4: const pw.FlexColumnWidth(1.2),
              5: const pw.FlexColumnWidth(1.2),
            }
          : {
              0: const pw.FlexColumnWidth(3),
              1: const pw.FlexColumnWidth(1),
              2: const pw.FlexColumnWidth(1.5),
              3: const pw.FlexColumnWidth(1.5),
            },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: headers
              .map((label) => pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(label)))
              .toList(),
        ),
        ...items.map((item) {
          final cells = hasLineDiscounts
              ? [
                  item.description,
                  item.quantity,
                  item.unitPrice,
                  item.lineSubtotal,
                  item.lineDiscountAmount,
                  item.lineTotal,
                ]
              : [item.description, item.quantity, item.unitPrice, item.lineTotal];
          return pw.TableRow(
            children: cells
                .map((value) => pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(value)))
                .toList(),
          );
        }),
      ],
    );
  }

  static pw.Widget _totalRow(String label, String value, String currency, {bool emphasized = false}) {
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
      child: pw.Text('${_formatDate(payment.recordedAt)} — ${payment.method.label} — $label ${payment.amount}'),
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
              style: pw.TextStyle(fontSize: 36, fontWeight: pw.FontWeight.bold, color: PdfColors.red800),
            ),
          ),
        ),
      ),
    );
  }

  static bool _itemHasLineDiscount(InvoiceItem item) {
    return _parseAmount(item.lineDiscountAmount) > 0;
  }

  static double _parseAmount(String value) {
    return double.tryParse(value) ?? 0;
  }

  static String _formatDate(DateTime value) {
    final local = value.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }
}

/// App bar / toolbar action to print an invoice receipt.
class ReceiptPrintButton extends StatelessWidget {
  const ReceiptPrintButton({super.key, required this.detail, this.organizationName});

  final InvoiceDetail detail;
  final String? organizationName;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: const Key('invoice_print_button'),
      tooltip: 'Print receipt',
      icon: const Icon(Icons.print_outlined),
      onPressed: () => ReceiptPrintPreview.printInvoice(detail, organizationName: organizationName),
    );
  }
}
