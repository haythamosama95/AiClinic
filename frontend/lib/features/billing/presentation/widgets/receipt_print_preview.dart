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
    final filename = pdfFileName(invoice);

    if (!context.mounted) {
      return;
    }

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('Print invoice')),
          body: PdfPreview(
            build: (_) async => (await buildDocument(invoice)).save(),
            pdfFileName: filename,
            canChangePageFormat: false,
            canChangeOrientation: false,
            canDebug: false,
            allowPrinting: true,
            allowSharing: false,
          ),
        ),
      ),
    );
  }

  static Future<pw.Document> buildDocument(InvoiceDetail invoice) async {
    return _ReceiptPdf.build(invoice);
  }

  static String pdfFileName(InvoiceDetail invoice) {
    final parts = <String>['aiclinc-invoice'];

    final number = invoice.invoiceNumber?.trim();
    if (number != null && number.isNotEmpty) {
      parts.add(_sanitizeFilenameSegment(number));
    } else {
      parts.add(invoice.id.substring(0, 8).toLowerCase());
    }

    final patient = invoice.patientDisplayName?.trim();
    if (patient != null && patient.isNotEmpty) {
      parts.add(_sanitizeFilenameSegment(patient));
    }

    final date = invoice.issuedAt ?? invoice.createdAt;
    parts.add(_formatDateForFilename(date));

    return '${parts.join('-')}.pdf';
  }

  static String _sanitizeFilenameSegment(String value) {
    final sanitized = value
        .replaceAll(RegExp(r'[^\w\-]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '')
        .toLowerCase();
    return sanitized.isEmpty ? 'invoice' : sanitized;
  }

  static String _formatDateForFilename(DateTime date) {
    final local = date.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '${local.year}-$month-$day';
  }
}

// ---------------------------------------------------------------------------
// PDF layout
// ---------------------------------------------------------------------------

abstract final class _ReceiptPalette {
  static const navy = PdfColor.fromInt(0xFF1A2B4A);
  static const teal = PdfColor.fromInt(0xFF0D7377);
  static const tealLight = PdfColor.fromInt(0xFFE8F4F4);
  static const surface = PdfColor.fromInt(0xFFF8FAFB);
  static const border = PdfColor.fromInt(0xFFDDE3EA);
  static const textMuted = PdfColor.fromInt(0xFF6B7A8D);
  static const textBody = PdfColor.fromInt(0xFF2C3E50);
  static const danger = PdfColor.fromInt(0xFFB42318);
  static const dangerBg = PdfColor.fromInt(0xFFFEF3F2);
  static const warning = PdfColor.fromInt(0xFFB54708);
  static const warningBg = PdfColor.fromInt(0xFFFFFAEB);
  static const success = PdfColor.fromInt(0xFF027A48);
  static const successBg = PdfColor.fromInt(0xFFECFDF3);
}

abstract final class _ReceiptTypography {
  static pw.TextStyle display({double size = 20, PdfColor color = _ReceiptPalette.navy}) {
    return pw.TextStyle(fontSize: size, fontWeight: pw.FontWeight.bold, color: color, letterSpacing: 0.5);
  }

  static pw.TextStyle label({PdfColor color = _ReceiptPalette.textMuted}) {
    return pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: color, letterSpacing: 1.2);
  }

  static pw.TextStyle body({bool bold = false, PdfColor color = _ReceiptPalette.textBody}) {
    return pw.TextStyle(fontSize: 10, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal, color: color);
  }

  static pw.TextStyle caption({PdfColor color = _ReceiptPalette.textMuted}) {
    return pw.TextStyle(fontSize: 8, color: color);
  }

  static pw.TextStyle amount({bool bold = false, PdfColor color = _ReceiptPalette.textBody}) {
    return pw.TextStyle(fontSize: 10, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal, color: color);
  }
}

abstract final class _ReceiptPdf {
  static Future<pw.Document> build(InvoiceDetail invoice) async {
    await pdfDefaultTheme();

    final doc = pw.Document();
    final currency = invoice.currency;
    final paidTotal = invoice.payments.fold<Money>(Money.zero, (sum, payment) => sum + payment.amount);
    final displayNumber = BillingFormatting.invoiceDisplayNumber(invoice.invoiceNumber, invoice.id);
    final watermark = switch (invoice.status) {
      InvoiceStatus.draft => 'DRAFT - NOT FOR PATIENT',
      InvoiceStatus.voided => 'VOIDED',
      _ => null,
    };

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 48, vertical: 40),
        header: (context) => _header(invoice, displayNumber),
        footer: (context) => _footer(context),
        build: (context) => [
          _metaSection(invoice),
          if (invoice.visitSummary != null) ...[pw.SizedBox(height: 16), _visitSummary(invoice.visitSummary!)],
          if (invoice.status.isVoided && invoice.voidReason != null) ...[pw.SizedBox(height: 16), _voidNotice(invoice)],
          pw.SizedBox(height: 24),
          _lineItemsTable(invoice, currency),
          pw.SizedBox(height: 20),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [pw.Spacer(), _totalsCard(invoice, currency, paidTotal)],
          ),
          if (invoice.payments.isNotEmpty) ...[pw.SizedBox(height: 28), _paymentsSection(invoice, currency)],
        ],
        pageTheme: watermark == null
            ? null
            : pw.PageTheme(
                pageFormat: PdfPageFormat.a4,
                margin: const pw.EdgeInsets.symmetric(horizontal: 48, vertical: 40),
                buildBackground: (context) => _watermark(watermark),
              ),
      ),
    );

    return doc;
  }

  static pw.Widget _header(InvoiceDetail invoice, String displayNumber) {
    final branchName = invoice.branchName?.trim();
    final branchCode = invoice.branchCode?.trim();
    final clinicName = branchName?.isNotEmpty == true ? branchName! : 'AiClinic';

    return pw.Column(
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _brandMark(),
            pw.SizedBox(width: 12),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(clinicName, style: _ReceiptTypography.display(size: 16)),
                  if (branchCode?.isNotEmpty == true)
                    pw.Text('Branch $branchCode', style: _ReceiptTypography.caption()),
                ],
              ),
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text('INVOICE RECEIPT', style: _ReceiptTypography.label(color: _ReceiptPalette.teal)),
                pw.SizedBox(height: 4),
                pw.Text(displayNumber, style: _ReceiptTypography.display(size: 18, color: _ReceiptPalette.teal)),
                pw.SizedBox(height: 6),
                _statusBadge(invoice.status),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 20),
        pw.Divider(color: _ReceiptPalette.border, thickness: 1),
        pw.SizedBox(height: 8),
      ],
    );
  }

  static pw.Widget _brandMark() {
    return pw.Container(
      width: 40,
      height: 40,
      decoration: pw.BoxDecoration(color: _ReceiptPalette.teal, borderRadius: pw.BorderRadius.circular(8)),
      alignment: pw.Alignment.center,
      child: pw.Text(
        'Rx',
        style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
      ),
    );
  }

  static pw.Widget _statusBadge(InvoiceStatus status) {
    final (bg, fg) = switch (status) {
      InvoiceStatus.draft => (_ReceiptPalette.warningBg, _ReceiptPalette.warning),
      InvoiceStatus.issued => (_ReceiptPalette.tealLight, _ReceiptPalette.teal),
      InvoiceStatus.partiallyPaid => (_ReceiptPalette.warningBg, _ReceiptPalette.warning),
      InvoiceStatus.paid => (_ReceiptPalette.successBg, _ReceiptPalette.success),
      InvoiceStatus.voided => (_ReceiptPalette.dangerBg, _ReceiptPalette.danger),
    };

    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: pw.BoxDecoration(color: bg, borderRadius: pw.BorderRadius.circular(12)),
      child: pw.Text(status.label.toUpperCase(), style: _ReceiptTypography.caption(color: fg)),
    );
  }

  static pw.Widget _metaSection(InvoiceDetail invoice) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        color: _ReceiptPalette.surface,
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(color: _ReceiptPalette.border),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(child: _metaColumn('Bill To', _billToRows(invoice))),
          pw.SizedBox(width: 24),
          pw.Expanded(child: _metaColumn('Invoice Details', _invoiceDetailRows(invoice))),
        ],
      ),
    );
  }

  static List<(String, String)> _billToRows(InvoiceDetail invoice) {
    return [
      ('Patient', invoice.patientDisplayName?.trim().isNotEmpty == true ? invoice.patientDisplayName! : '-'),
      ('Phone', invoice.patientPhone?.trim().isNotEmpty == true ? invoice.patientPhone! : '-'),
    ];
  }

  static List<(String, String)> _invoiceDetailRows(InvoiceDetail invoice) {
    return [
      ('Branch', invoice.branchName?.trim().isNotEmpty == true ? invoice.branchName! : '-'),
      ('Issued', invoice.issuedAt == null ? 'Not yet issued' : BillingFormatting.formatDate(invoice.issuedAt!)),
      ('Created', BillingFormatting.formatDate(invoice.createdAt)),
      if (invoice.status.isVoided && invoice.voidedAt != null)
        ('Voided', BillingFormatting.formatDateTime(invoice.voidedAt!)),
    ];
  }

  static pw.Widget _metaColumn(String title, List<(String, String)> rows) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(title.toUpperCase(), style: _ReceiptTypography.label()),
        pw.SizedBox(height: 8),
        for (final (label, value) in rows) ...[
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 6),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.SizedBox(width: 64, child: pw.Text(label, style: _ReceiptTypography.caption())),
                pw.Expanded(child: pw.Text(value, style: _ReceiptTypography.body())),
              ],
            ),
          ),
        ],
      ],
    );
  }

  static pw.Widget _visitSummary(VisitSummary visit) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: pw.BoxDecoration(color: _ReceiptPalette.tealLight, borderRadius: pw.BorderRadius.circular(8)),
      child: pw.Row(
        children: [
          pw.Text('VISIT', style: _ReceiptTypography.label(color: _ReceiptPalette.teal)),
          pw.SizedBox(width: 16),
          pw.Expanded(
            child: pw.Text(
              '${BillingFormatting.formatDate(visit.date)} - ${visit.doctor} - ${visit.branch}',
              style: _ReceiptTypography.body(),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _voidNotice(InvoiceDetail invoice) {
    final reason = invoice.voidReason ?? '-';
    final voidedBy = invoice.voidedByName?.trim();
    final detail = voidedBy?.isNotEmpty == true ? '$reason (by $voidedBy)' : reason;

    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: _ReceiptPalette.dangerBg,
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(color: _ReceiptPalette.danger),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('VOIDED INVOICE', style: _ReceiptTypography.label(color: _ReceiptPalette.danger)),
          pw.SizedBox(height: 4),
          pw.Text(detail, style: _ReceiptTypography.body(color: _ReceiptPalette.danger)),
        ],
      ),
    );
  }

  static pw.Widget _lineItemsTable(InvoiceDetail invoice, String currency) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('LINE ITEMS', style: _ReceiptTypography.label()),
        pw.SizedBox(height: 8),
        pw.Table(
          border: pw.TableBorder(horizontalInside: pw.BorderSide(color: _ReceiptPalette.border, width: 0.5)),
          columnWidths: {
            0: const pw.FlexColumnWidth(4),
            1: const pw.FixedColumnWidth(40),
            2: const pw.FixedColumnWidth(72),
            3: const pw.FixedColumnWidth(72),
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: _ReceiptPalette.teal),
              children: [
                _tableHeaderCell('Description', align: pw.TextAlign.left),
                _tableHeaderCell('Qty'),
                _tableHeaderCell('Unit', align: pw.TextAlign.right),
                _tableHeaderCell('Total', align: pw.TextAlign.right),
              ],
            ),
            for (final item in invoice.items)
              pw.TableRow(
                children: [
                  _tableCell(item.description, align: pw.TextAlign.left),
                  _tableCell(item.quantity, align: pw.TextAlign.center),
                  _tableCell(_formatMoney(item.unitPrice, currency), align: pw.TextAlign.right, amount: true),
                  _tableCell(
                    _formatMoney(item.lineTotal, currency),
                    align: pw.TextAlign.right,
                    amount: true,
                    bold: true,
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }

  static pw.Widget _tableHeaderCell(String text, {pw.TextAlign align = pw.TextAlign.center}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: pw.Text(
        text.toUpperCase(),
        textAlign: align,
        style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white, letterSpacing: 0.8),
      ),
    );
  }

  static String _formatMoney(Money amount, String currency) {
    return BillingFormatting.formatMoney(amount, currency: currency);
  }

  static pw.Widget _tableCell(
    String text, {
    pw.TextAlign align = pw.TextAlign.left,
    bool bold = false,
    bool amount = false,
  }) {
    final style = amount ? _ReceiptTypography.amount(bold: bold) : _ReceiptTypography.body(bold: bold);
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: pw.Text(text, textAlign: align, style: style),
    );
  }

  static pw.Widget _totalsCard(InvoiceDetail invoice, String currency, Money paidTotal) {
    final balanceLabel = invoice.status.isVoided ? 'Balance at void' : 'Balance due';

    return pw.Container(
      width: 240,
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        color: _ReceiptPalette.surface,
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(color: _ReceiptPalette.border),
      ),
      child: pw.Column(
        children: [
          _totalRow('Subtotal', _formatMoney(invoice.subtotal, currency)),
          if (!invoice.discountAmount.isZero)
            _totalRow('Discount', '-${_formatMoney(invoice.discountAmount, currency)}'),
          if (!invoice.insuranceCoveredAmount.isZero)
            _totalRow(
              invoice.insuranceProviderName ?? 'Insurance',
              '-${_formatMoney(invoice.insuranceCoveredAmount, currency)}',
            ),
          if (!paidTotal.isZero) _totalRow('Paid', _formatMoney(paidTotal, currency)),
          pw.SizedBox(height: 8),
          pw.Divider(color: _ReceiptPalette.border),
          pw.SizedBox(height: 8),
          _totalRow(
            balanceLabel,
            _formatMoney(invoice.balance, currency),
            bold: true,
            valueColor: _ReceiptPalette.teal,
          ),
        ],
      ),
    );
  }

  static pw.Widget _totalRow(String label, String value, {bool bold = false, PdfColor? valueColor}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: _ReceiptTypography.body(bold: bold)),
          pw.Text(
            value,
            style: _ReceiptTypography.amount(bold: bold, color: valueColor ?? _ReceiptPalette.textBody),
          ),
        ],
      ),
    );
  }

  static pw.Widget _paymentsSection(InvoiceDetail invoice, String currency) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('PAYMENT HISTORY', style: _ReceiptTypography.label()),
        pw.SizedBox(height: 8),
        pw.Table(
          border: pw.TableBorder(horizontalInside: pw.BorderSide(color: _ReceiptPalette.border, width: 0.5)),
          columnWidths: {
            0: const pw.FlexColumnWidth(2),
            1: const pw.FixedColumnWidth(88),
            2: const pw.FlexColumnWidth(2),
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: _ReceiptPalette.navy),
              children: [
                _tableHeaderCell('Method', align: pw.TextAlign.left),
                _tableHeaderCell('Amount', align: pw.TextAlign.right),
                _tableHeaderCell('Date', align: pw.TextAlign.right),
              ],
            ),
            for (final payment in invoice.payments)
              pw.TableRow(
                children: [
                  _tableCell(payment.method.label, align: pw.TextAlign.left),
                  _tableCell(_formatMoney(payment.amount, currency), align: pw.TextAlign.right, amount: true),
                  _tableCell(BillingFormatting.formatDateTime(payment.recordedAt), align: pw.TextAlign.right),
                ],
              ),
          ],
        ),
      ],
    );
  }

  static pw.Widget _footer(pw.Context context) {
    return pw.Column(
      children: [
        pw.Divider(color: _ReceiptPalette.border),
        pw.SizedBox(height: 8),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Thank you for choosing our clinic.', style: _ReceiptTypography.caption()),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    'This document is a billing receipt. Please retain for your records.',
                    style: _ReceiptTypography.caption(),
                  ),
                ],
              ),
            ),
            pw.Text('Page ${context.pageNumber} of ${context.pagesCount}', style: _ReceiptTypography.caption()),
          ],
        ),
      ],
    );
  }

  static pw.Widget _watermark(String text) {
    return pw.FullPage(
      ignoreMargins: true,
      child: pw.Center(
        child: pw.Transform.rotate(
          angle: -0.4,
          child: pw.Opacity(
            opacity: 0.08,
            child: pw.Text(
              text,
              style: pw.TextStyle(fontSize: 48, fontWeight: pw.FontWeight.bold, color: _ReceiptPalette.textMuted),
            ),
          ),
        ),
      ),
    );
  }
}
