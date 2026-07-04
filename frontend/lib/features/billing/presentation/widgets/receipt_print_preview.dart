import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfx/pdfx.dart' as pdfx;
import 'package:printing/printing.dart';

import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/billing/domain/invoice_detail.dart';
import 'package:ai_clinic/features/billing/domain/invoice_status.dart';
import 'package:ai_clinic/features/billing/domain/money.dart';
import 'package:ai_clinic/features/billing/presentation/utils/billing_formatting.dart';

/// Builds a printable receipt PDF and shows an in-app preview (V1-6 US7).
abstract final class ReceiptPrintPreview {
  static Future<void> show(BuildContext context, InvoiceDetail invoice) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => _ReceiptPreviewPage(invoice: invoice)),
    );
  }

  static Future<pw.Document> buildDocument(InvoiceDetail invoice) async {
    final doc = pw.Document();
    final currency = invoice.currency;
    final paidTotal = invoice.payments.fold<Money>(Money.zero, (sum, payment) => sum + payment.amount);
    final watermark = switch (invoice.status) {
      InvoiceStatus.draft => 'DRAFT',
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
                style: pw.TextStyle(fontSize: 48, color: PdfColors.grey300, fontWeight: pw.FontWeight.bold),
              ),
            ),
          pw.SizedBox(height: 12),
          pw.Text('Invoice receipt', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          pw.Text(BillingFormatting.invoiceDisplayNumber(invoice.invoiceNumber, invoice.id)),
          if (invoice.branchName != null) pw.Text('Branch: ${invoice.branchName}'),
          if (invoice.patientDisplayName != null) pw.Text('Patient: ${invoice.patientDisplayName}'),
          if (invoice.issuedAt != null) pw.Text('Issued: ${BillingFormatting.formatDateTime(invoice.issuedAt!)}'),
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

enum _ReceiptPreviewMode { pdfx, raster, external }

class _ReceiptPreviewPage extends StatefulWidget {
  const _ReceiptPreviewPage({required this.invoice});

  final InvoiceDetail invoice;

  @override
  State<_ReceiptPreviewPage> createState() => _ReceiptPreviewPageState();
}

class _ReceiptPreviewPageState extends State<_ReceiptPreviewPage> {
  pdfx.PdfControllerPinch? _pdfxController;
  Uint8List? _bytes;
  Object? _error;
  _ReceiptPreviewMode? _mode;
  List<ui.Image> _rasterPages = const [];
  var _isSaving = false;
  var _isPrinting = false;
  var _isOpening = false;

  @override
  void initState() {
    super.initState();
    _loadPreview();
  }

  Future<void> _loadPreview() async {
    try {
      final bytes = await (await ReceiptPrintPreview.buildDocument(widget.invoice)).save();
      if (!mounted) {
        return;
      }

      if (await pdfx.hasPdfSupport()) {
        setState(() {
          _bytes = bytes;
          _mode = _ReceiptPreviewMode.pdfx;
          _pdfxController = pdfx.PdfControllerPinch(document: pdfx.PdfDocument.openData(bytes));
        });
        return;
      }

      final info = await Printing.info();
      if (info.canRaster) {
        final pages = <ui.Image>[];
        await for (final page in Printing.raster(bytes)) {
          pages.add(await page.toImage());
        }
        if (!mounted) {
          return;
        }
        setState(() {
          _bytes = bytes;
          _mode = _ReceiptPreviewMode.raster;
          _rasterPages = pages;
        });
        return;
      }

      setState(() {
        _bytes = bytes;
        _mode = _ReceiptPreviewMode.external;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _error = error);
    }
  }

  @override
  void dispose() {
    _pdfxController?.dispose();
    for (final page in _rasterPages) {
      page.dispose();
    }
    super.dispose();
  }

  Future<void> _savePdf() async {
    final bytes = _bytes;
    if (bytes == null || _isSaving) {
      return;
    }

    setState(() => _isSaving = true);
    try {
      final fileName = ReceiptPrintPreview.pdfFileName(widget.invoice);
      if (kIsWeb) {
        final path = await FilePicker.platform.saveFile(
          fileName: fileName,
          type: FileType.custom,
          allowedExtensions: const ['pdf'],
          bytes: bytes,
        );
        if (path == null) {
          return;
        }
      } else {
        final path = await FilePicker.platform.saveFile(
          fileName: fileName,
          type: FileType.custom,
          allowedExtensions: const ['pdf'],
        );
        if (path == null) {
          return;
        }
        await File(path).writeAsBytes(bytes, flush: true);
      }
      if (mounted) {
        AppToast.success(context, message: 'Receipt saved.');
      }
    } catch (_) {
      if (mounted) {
        AppToast.error(context, message: 'Unable to save receipt.');
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _printPdf() async {
    final bytes = _bytes;
    if (bytes == null || _isPrinting) {
      return;
    }

    setState(() => _isPrinting = true);
    try {
      final info = await Printing.info();
      if (info.canPrint) {
        final printed = await Printing.layoutPdf(
          name: ReceiptPrintPreview.pdfFileName(widget.invoice),
          onLayout: (_) async => bytes,
        );
        if (printed) {
          return;
        }
      }
    } catch (_) {
      // Fall back to opening in the system viewer below.
    }

    try {
      await _openPdfWithSystemViewer(bytes, ReceiptPrintPreview.pdfFileName(widget.invoice));
    } catch (_) {
      if (mounted) {
        AppToast.error(context, message: 'Unable to print receipt. Try saving as PDF instead.');
      }
    } finally {
      if (mounted) {
        setState(() => _isPrinting = false);
      }
    }
  }

  Future<void> _openPdfWithSystemViewer(Uint8List bytes, String filename) async {
    if (kIsWeb) {
      final path = await FilePicker.platform.saveFile(
        fileName: filename,
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
        bytes: bytes,
      );
      if (path == null) {
        throw StateError('Save cancelled');
      }
      return;
    }

    final directory = await getTemporaryDirectory();
    final receiptsDir = Directory('${directory.path}/receipt_previews');
    if (!await receiptsDir.exists()) {
      await receiptsDir.create(recursive: true);
    }

    final path = '${receiptsDir.path}/${DateTime.now().microsecondsSinceEpoch}_$filename';
    await File(path).writeAsBytes(bytes, flush: true);

    final result = await OpenFilex.open(path);
    if (result.type != ResultType.done) {
      throw StateError(result.message);
    }
  }

  Future<void> _openExternally() async {
    final bytes = _bytes;
    if (bytes == null || _isOpening) {
      return;
    }

    setState(() => _isOpening = true);
    try {
      await _openPdfWithSystemViewer(bytes, ReceiptPrintPreview.pdfFileName(widget.invoice));
    } catch (_) {
      if (mounted) {
        AppToast.error(context, message: 'Unable to open receipt.');
      }
    } finally {
      if (mounted) {
        setState(() => _isOpening = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: colors.background,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(SpacingTokens.lg, SpacingTokens.lg, SpacingTokens.lg, SpacingTokens.md),
            child: Row(
              children: [
                AppIconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: SpacingTokens.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Receipt preview',
                        style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        BillingFormatting.invoiceDisplayNumber(widget.invoice.invoiceNumber, widget.invoice.id),
                        style: theme.textTheme.bodyMedium?.copyWith(color: colors.mutedForeground),
                      ),
                    ],
                  ),
                ),
                if (_mode != _ReceiptPreviewMode.external) ...[
                  AppButton(
                    label: 'Save PDF',
                    variant: AppButtonVariant.outline,
                    expand: false,
                    isLoading: _isSaving,
                    icon: const Icon(Icons.download_outlined, size: 18),
                    onPressed: _bytes == null || _isSaving ? null : _savePdf,
                  ),
                  const SizedBox(width: SpacingTokens.sm),
                  AppButton(
                    label: 'Print',
                    expand: false,
                    isLoading: _isPrinting,
                    icon: const Icon(Icons.print_outlined, size: 18),
                    onPressed: _bytes == null || _isPrinting ? null : _printPdf,
                  ),
                ],
              ],
            ),
          ),
          Expanded(child: _buildBody(context)),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final colors = context.semanticColors;
    final theme = Theme.of(context);

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(SpacingTokens.lg),
          child: Text('Unable to render receipt: $_error', textAlign: TextAlign.center),
        ),
      );
    }

    if (_mode == null) {
      return const Center(child: AppCircularProgress());
    }

    return switch (_mode!) {
      _ReceiptPreviewMode.pdfx => ColoredBox(
        color: colors.muted,
        child: pdfx.PdfViewPinch(
          controller: _pdfxController!,
          builders: pdfx.PdfViewPinchBuilders<pdfx.DefaultBuilderOptions>(
            options: const pdfx.DefaultBuilderOptions(),
            documentLoaderBuilder: (_) => const Center(child: AppCircularProgress()),
            pageLoaderBuilder: (_) => const Center(child: AppCircularProgress()),
            errorBuilder: (_, error) => Center(child: Text('Unable to render receipt: $error')),
          ),
        ),
      ),
      _ReceiptPreviewMode.raster => ColoredBox(
        color: colors.muted,
        child: ListView.builder(
          padding: const EdgeInsets.all(SpacingTokens.lg),
          itemCount: _rasterPages.length,
          itemBuilder: (context, index) {
            return Padding(
              padding: const EdgeInsets.only(bottom: SpacingTokens.md),
              child: Center(
                child: RawImage(image: _rasterPages[index], fit: BoxFit.contain),
              ),
            );
          },
        ),
      ),
      _ReceiptPreviewMode.external => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(SpacingTokens.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.picture_as_pdf_outlined, size: 48, color: colors.mutedForeground),
                const SizedBox(height: SpacingTokens.md),
                Text(
                  'Receipt ready',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: SpacingTokens.sm),
                Text(
                  'In-app preview is not available on this platform. Open the PDF in your default viewer or save it locally.',
                  style: theme.textTheme.bodyMedium?.copyWith(color: colors.mutedForeground),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: SpacingTokens.lg),
                AppButton(
                  label: 'Open PDF',
                  expand: false,
                  isLoading: _isOpening,
                  icon: const Icon(Icons.open_in_new, size: 18),
                  onPressed: _bytes == null || _isOpening ? null : _openExternally,
                ),
                const SizedBox(height: SpacingTokens.sm),
                AppButton(
                  label: 'Save PDF',
                  variant: AppButtonVariant.outline,
                  expand: false,
                  isLoading: _isSaving,
                  icon: const Icon(Icons.download_outlined, size: 18),
                  onPressed: _bytes == null || _isSaving ? null : _savePdf,
                ),
                if (!kIsWeb) ...[
                  const SizedBox(height: SpacingTokens.sm),
                  AppButton(
                    label: 'Print',
                    variant: AppButtonVariant.outline,
                    expand: false,
                    isLoading: _isPrinting,
                    icon: const Icon(Icons.print_outlined, size: 18),
                    onPressed: _bytes == null || _isPrinting ? null : _printPdf,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    };
  }
}
