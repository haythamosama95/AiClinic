import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:ai_clinic/core/money/money.dart';
import 'package:ai_clinic/core/ui/components/app_avatar.dart';
import 'package:ai_clinic/core/ui/components/app_money_display.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/billing/domain/visit_billing_models.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/invoice_perforation_divider.dart';

/// Server-sourced or preview totals rendered in the invoice document card.
@immutable
class VisitInvoiceDocumentTotals {
  const VisitInvoiceDocumentTotals({
    required this.subtotal,
    required this.discountAmount,
    required this.amountDue,
    this.insuranceCoveredAmount,
    this.balance,
  });

  final Money subtotal;
  final Money discountAmount;
  final Money amountDue;
  final Money? insuranceCoveredAmount;
  final Money? balance;

  factory VisitInvoiceDocumentTotals.fromPreview(VisitBillingTotals totals) {
    return VisitInvoiceDocumentTotals(
      subtotal: totals.subtotal,
      discountAmount: totals.discountAmount,
      amountDue: totals.total,
    );
  }
}

/// Printable invoice document: header, patient block, line table, and totals.
class VisitInvoiceDocumentCard extends StatelessWidget {
  const VisitInvoiceDocumentCard({
    required this.previewNumber,
    required this.lines,
    required this.totals,
    required this.discountType,
    required this.discountValue,
    required this.currency,
    required this.patientName,
    this.patientPhone,
    this.headerTitle = 'Review invoice',
    this.showStepLabel = true,
    this.statusBadge,
    this.issuedAt,
    super.key,
  });

  final String previewNumber;
  final List<VisitSelectedServiceLine> lines;
  final VisitInvoiceDocumentTotals totals;
  final VisitBillingDiscountType discountType;
  final Decimal discountValue;
  final String currency;
  final String patientName;
  final String? patientPhone;
  final String headerTitle;
  final bool showStepLabel;
  final Widget? statusBadge;
  final DateTime? issuedAt;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final elevation = context.appElevation;
    final issuedDate = DateFormat(
      'd MMM yyyy',
    ).format((issuedAt ?? DateTime.now()).toLocal());

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceRaised,
        border: Border.all(color: colors.borderSubtle),
        borderRadius: BorderRadius.circular(AppRadius.x2l),
        boxShadow: elevation.shadows1,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.x2l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InvoicePerforationDivider(
              color: colors.borderDefault.withValues(alpha: 0.4),
              dashWidth: 6,
              gap: 6,
              showNotches: false,
              verticalPadding: 0,
              lineHeight: 6,
              filled: true,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.space6,
                AppSpacing.space5,
                AppSpacing.space6,
                AppSpacing.space5,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: headerTitle,
                                style: AppTypography.bodySm(context).copyWith(
                                  color: colors.textPrimary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              if (showStepLabel)
                                TextSpan(
                                  text: ' · Step 2 of 2',
                                  style: AppTypography.bodySm(
                                    context,
                                  ).copyWith(color: colors.textTertiary),
                                ),
                            ],
                          ),
                        ),
                      ),
                      statusBadge ??
                          const AppBadge(
                            label: 'Draft',
                            color: BadgeColor.warning,
                          ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.space5),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppAvatar(name: patientName, size: AvatarSize.lg),
                      const SizedBox(width: AppSpacing.space4),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    patientName,
                                    style: AppTypography.h2(
                                      context,
                                    ).copyWith(color: colors.textPrimary),
                                  ),
                                ),
                                Text(
                                  previewNumber,
                                  style: AppTypography.bodySm(context).copyWith(
                                    color: colors.textPrimary,
                                    fontFamily: 'monospace',
                                    letterSpacing: 0.8,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.space2),
                            Text.rich(
                              TextSpan(
                                children: [
                                  if (patientPhone != null &&
                                      patientPhone!.trim().isNotEmpty)
                                    TextSpan(
                                      text: patientPhone!.trim(),
                                      style: AppTypography.bodySm(
                                        context,
                                      ).copyWith(color: colors.textSecondary),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: AppSpacing.space1),
                            Text(
                              issuedDate,
                              style: AppTypography.bodySm(context).copyWith(
                                color: colors.textSecondary,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.space6,
                0,
                AppSpacing.space6,
                AppSpacing.space5,
              ),
              child: VisitInvoiceLineTable(lines: lines, currency: currency),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                color: colors.surfaceSunken.withValues(alpha: 0.2),
                border: Border(
                  top: BorderSide(
                    color: colors.borderDefault,
                    style: BorderStyle.solid,
                  ),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.space6,
                  AppSpacing.space5,
                  AppSpacing.space6,
                  AppSpacing.space5,
                ),
                child: Column(
                  children: [
                    _VisitInvoiceTotalRow(
                      label: 'Subtotal',
                      child: AppMoneyDisplay(
                        amount: totals.subtotal,
                        currency: currency,
                      ),
                    ),
                    if (totals.discountAmount.isPositive) ...[
                      const SizedBox(height: AppSpacing.space2),
                      _VisitInvoiceTotalRow(
                        label:
                            discountType == VisitBillingDiscountType.percentage
                            ? 'Discount (${_discountPercentLabel(discountValue)})'
                            : 'Discount',
                        child: AppMoneyDisplay(
                          amount: totals.discountAmount,
                          currency: currency,
                          negative: true,
                        ),
                        labelColor: colors.statusSuccessFg,
                      ),
                    ],
                    if (totals.insuranceCoveredAmount?.isPositive == true) ...[
                      const SizedBox(height: AppSpacing.space2),
                      _VisitInvoiceTotalRow(
                        label: 'Insurance covered',
                        child: AppMoneyDisplay(
                          amount: totals.insuranceCoveredAmount!,
                          currency: currency,
                          negative: true,
                        ),
                        labelColor: colors.statusSuccessFg,
                      ),
                    ],
                    const SizedBox(height: AppSpacing.space3),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(color: colors.borderSubtle),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.space3),
                        child: _VisitInvoiceTotalRow(
                          label: totals.balance != null
                              ? 'Amount due'
                              : 'Total due',
                          labelStyle: AppTypography.bodyStrong(
                            context,
                          ).copyWith(color: colors.textPrimary),
                          child: DefaultTextStyle(
                            style: AppTypography.h2(
                              context,
                            ).copyWith(color: colors.textPrimary),
                            child: AppMoneyDisplay(
                              amount: totals.amountDue,
                              currency: currency,
                              emphasis: true,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (totals.balance != null) ...[
                      const SizedBox(height: AppSpacing.space2),
                      _VisitInvoiceTotalRow(
                        label: 'Balance',
                        labelStyle: AppTypography.bodyStrong(
                          context,
                        ).copyWith(color: colors.textPrimary),
                        child: AppMoneyDisplay(
                          amount: totals.balance!,
                          currency: currency,
                          emphasis: true,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _discountPercentLabel(Decimal value) {
    final rounded = value.round(scale: 0);
    if (value == rounded) {
      return rounded.toString();
    }
    return value.toString();
  }
}

class VisitInvoiceLineTable extends StatelessWidget {
  const VisitInvoiceLineTable({
    required this.lines,
    required this.currency,
    super.key,
  });

  final List<VisitSelectedServiceLine> lines;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return LayoutBuilder(
      builder: (context, constraints) {
        final showUnit = constraints.maxWidth >= 640;

        return Table(
          columnWidths: const {
            0: FlexColumnWidth(2),
            1: FlexColumnWidth(1),
            2: FixedColumnWidth(48),
            3: FlexColumnWidth(1),
          },
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            TableRow(
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: colors.borderSubtle)),
              ),
              children: [
                _VisitInvoiceTableHeaderCell('Service'),
                if (showUnit)
                  _VisitInvoiceTableHeaderCell('Unit', align: TextAlign.end),
                _VisitInvoiceTableHeaderCell('Qty', align: TextAlign.center),
                _VisitInvoiceTableHeaderCell('Amount', align: TextAlign.end),
              ],
            ),
            for (final line in lines)
              TableRow(
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: colors.borderSubtle.withValues(alpha: 0.7),
                    ),
                  ),
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.space3 + 2,
                    ),
                    child: Text(
                      line.name,
                      style: AppTypography.bodySm(
                        context,
                      ).copyWith(color: colors.textPrimary),
                    ),
                  ),
                  if (showUnit)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.space3 + 2,
                      ),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: AppMoneyDisplay(
                          amount: line.unitPrice,
                          currency: currency,
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.space3 + 2,
                    ),
                    child: Text(
                      '${line.quantity}',
                      textAlign: TextAlign.center,
                      style: AppTypography.bodySm(context).copyWith(
                        color: colors.textSecondary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.space3 + 2,
                    ),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: AppMoneyDisplay(
                        amount: line.lineTotal,
                        currency: currency,
                      ),
                    ),
                  ),
                ],
              ),
          ],
        );
      },
    );
  }
}

class _VisitInvoiceTableHeaderCell extends StatelessWidget {
  const _VisitInvoiceTableHeaderCell(this.label, {this.align = TextAlign.start});

  final String label;
  final TextAlign align;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.space2 + 2),
      child: Text(
        label.toUpperCase(),
        textAlign: align,
        style: AppTypography.overline(
          context,
        ).copyWith(color: context.appColors.textTertiary),
      ),
    );
  }
}

class _VisitInvoiceTotalRow extends StatelessWidget {
  const _VisitInvoiceTotalRow({
    required this.label,
    required this.child,
    this.labelStyle,
    this.labelColor,
  });

  final String label;
  final Widget child;
  final TextStyle? labelStyle;
  final Color? labelColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style:
                labelStyle ??
                AppTypography.bodySm(
                  context,
                ).copyWith(color: labelColor ?? colors.textSecondary),
          ),
        ),
        child,
      ],
    );
  }
}
