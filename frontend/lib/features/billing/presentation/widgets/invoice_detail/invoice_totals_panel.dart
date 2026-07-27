import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/components/app_money_display.dart';
import 'package:ai_clinic/features/billing/domain/discount_kind.dart';
import 'package:ai_clinic/features/billing/presentation/utils/billing_formatting.dart';
import 'package:ai_clinic/features/billing/presentation/utils/invoice_labels.dart';
import 'package:ai_clinic/core/money/money.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

/// Variant selector for the shared invoice totals panel.
enum InvoiceTotalsVariant { lineItems, payments }

/// Typed totals payload for [InvoiceTotalsPanel].
sealed class InvoiceTotalsModel {
  const InvoiceTotalsModel();

  const factory InvoiceTotalsModel.lineItems({
    required Money subtotal,
    required Money discountAmount,
    DiscountKind? discountKind,
    String? discountValue,
    required Money insuranceCoveredAmount,
    String? insuranceProviderName,
    required Money amountDue,
    required String currency,
  }) = LineItemsInvoiceTotalsModel;

  const factory InvoiceTotalsModel.payments({
    required Money amountDue,
    required Money netPaid,
    required Money balance,
    required String currency,
    required bool isVoided,
    required bool hasPayments,
  }) = PaymentsInvoiceTotalsModel;
}

final class LineItemsInvoiceTotalsModel extends InvoiceTotalsModel {
  const LineItemsInvoiceTotalsModel({
    required this.subtotal,
    required this.discountAmount,
    this.discountKind,
    this.discountValue,
    required this.insuranceCoveredAmount,
    this.insuranceProviderName,
    required this.amountDue,
    required this.currency,
  });

  final Money subtotal;
  final Money discountAmount;
  final DiscountKind? discountKind;
  final String? discountValue;
  final Money insuranceCoveredAmount;
  final String? insuranceProviderName;
  final Money amountDue;
  final String currency;
}

final class PaymentsInvoiceTotalsModel extends InvoiceTotalsModel {
  const PaymentsInvoiceTotalsModel({
    required this.amountDue,
    required this.netPaid,
    required this.balance,
    required this.currency,
    required this.isVoided,
    required this.hasPayments,
  });

  final Money amountDue;
  final Money netPaid;
  final Money balance;
  final String currency;
  final bool isVoided;
  final bool hasPayments;
}

/// Dashed-top totals block shared by the line-items and payments cards.
class InvoiceTotalsPanel extends StatelessWidget {
  const InvoiceTotalsPanel({required this.model, super.key});

  final InvoiceTotalsModel model;

  static const _panelMaxWidth = 384.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return DecoratedBox(
      decoration: BoxDecoration(color: colors.surfaceSunken.withValues(alpha: 0.2)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const _DashedTopLine(),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.space6,
              AppSpacing.space5,
              AppSpacing.space6,
              AppSpacing.space5,
            ),
            child: Align(
              alignment: Alignment.centerRight,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _panelMaxWidth),
                child: switch (model) {
                  LineItemsInvoiceTotalsModel(
                    :final subtotal,
                    :final discountAmount,
                    :final discountKind,
                    :final discountValue,
                    :final insuranceCoveredAmount,
                    :final insuranceProviderName,
                    :final amountDue,
                    :final currency,
                  ) =>
                    _LineItemsTotalsContent(
                      subtotal: subtotal,
                      discountAmount: discountAmount,
                      discountKind: discountKind,
                      discountValue: discountValue,
                      insuranceCoveredAmount: insuranceCoveredAmount,
                      insuranceProviderName: insuranceProviderName,
                      amountDue: amountDue,
                      currency: currency,
                    ),
                  PaymentsInvoiceTotalsModel(
                    :final amountDue,
                    :final netPaid,
                    :final balance,
                    :final currency,
                    :final isVoided,
                    :final hasPayments,
                  ) =>
                    _PaymentsTotalsContent(
                      amountDue: amountDue,
                      netPaid: netPaid,
                      balance: balance,
                      currency: currency,
                      isVoided: isVoided,
                      hasPayments: hasPayments,
                    ),
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LineItemsTotalsContent extends StatelessWidget {
  const _LineItemsTotalsContent({
    required this.subtotal,
    required this.discountAmount,
    this.discountKind,
    this.discountValue,
    required this.insuranceCoveredAmount,
    this.insuranceProviderName,
    required this.amountDue,
    required this.currency,
  });

  final Money subtotal;
  final Money discountAmount;
  final DiscountKind? discountKind;
  final String? discountValue;
  final Money insuranceCoveredAmount;
  final String? insuranceProviderName;
  final Money amountDue;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final discountSuffix = discountKind != null
        ? ' (${BillingFormatting.discountLabel(discountKind, discountValue, currency: currency)})'
        : '';
    final providerSuffix = insuranceProviderName?.trim().isNotEmpty == true
        ? ' (${insuranceProviderName!.trim()})'
        : '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _TotalsRow(
          label: 'Subtotal',
          value: AppMoneyDisplay(amount: subtotal, currency: currency),
        ),
        if (!discountAmount.isZero) ...[
          const SizedBox(height: AppSpacing.space2),
          _TotalsRow(
            labelWidget: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.local_offer_outlined, size: 13, color: colors.statusSuccessFg),
                const SizedBox(width: AppSpacing.space1 + AppSpacing.space05),
                Flexible(
                  child: Text(
                    'Invoice discount$discountSuffix',
                    style: AppTypography.bodySm(context).copyWith(color: colors.statusSuccessFg),
                  ),
                ),
              ],
            ),
            value: AppMoneyDisplay(amount: discountAmount, currency: currency, negative: true),
            valueColor: colors.statusSuccessFg,
          ),
        ],
        if (!insuranceCoveredAmount.isZero) ...[
          const SizedBox(height: AppSpacing.space2),
          _TotalsRow(
            labelWidget: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.shield_outlined, size: 13, color: colors.statusSuccessFg),
                const SizedBox(width: AppSpacing.space1 + AppSpacing.space05),
                Flexible(
                  child: Text(
                    'Insurance covered$providerSuffix',
                    style: AppTypography.bodySm(context).copyWith(color: colors.statusSuccessFg),
                  ),
                ),
              ],
            ),
            value: AppMoneyDisplay(amount: insuranceCoveredAmount, currency: currency, negative: true),
            valueColor: colors.statusSuccessFg,
          ),
        ],
        const SizedBox(height: AppSpacing.space3),
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: colors.borderSubtle)),
          ),
          child: Padding(
            padding: const EdgeInsets.only(top: AppSpacing.space3),
            child: _TotalsRow(
              label: 'Amount due',
              labelEmphasized: true,
              value: DefaultTextStyle(
                style: AppTypography.h2(context).copyWith(color: colors.textPrimary),
                child: AppMoneyDisplay(amount: amountDue, currency: currency, emphasis: true),
              ),
              valueEmphasized: true,
            ),
          ),
        ),
      ],
    );
  }
}

class _PaymentsTotalsContent extends StatelessWidget {
  const _PaymentsTotalsContent({
    required this.amountDue,
    required this.netPaid,
    required this.balance,
    required this.currency,
    required this.isVoided,
    required this.hasPayments,
  });

  final Money amountDue;
  final Money netPaid;
  final Money balance;
  final String currency;
  final bool isVoided;
  final bool hasPayments;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final balanceLabel = InvoiceLabels.balanceLabel(isVoided: isVoided);
    final balanceColor = InvoiceLabels.showsSettledStyling(balance: balance, isVoided: isVoided)
        ? colors.statusSuccessFg
        : colors.textPrimary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _TotalsRow(
          label: 'Amount due',
          value: AppMoneyDisplay(amount: amountDue, currency: currency, emphasis: true),
        ),
        if (hasPayments) ...[
          const SizedBox(height: AppSpacing.space2),
          _TotalsRow(
            label: 'Net paid',
            value: AppMoneyDisplay(amount: netPaid, currency: currency),
          ),
        ],
        const SizedBox(height: AppSpacing.space3),
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: colors.borderSubtle)),
          ),
          child: Padding(
            padding: const EdgeInsets.only(top: AppSpacing.space3),
            child: _TotalsRow(
              label: balanceLabel,
              labelEmphasized: true,
              value: DefaultTextStyle(
                style: AppTypography.h2(context).copyWith(color: balanceColor),
                child: AppMoneyDisplay(amount: balance, currency: currency, emphasis: true),
              ),
              valueEmphasized: true,
              valueColor: balanceColor,
            ),
          ),
        ),
      ],
    );
  }
}

class _TotalsRow extends StatelessWidget {
  const _TotalsRow({
    this.label,
    this.labelWidget,
    required this.value,
    this.labelEmphasized = false,
    this.valueEmphasized = false,
    this.valueColor,
  }) : assert(label != null || labelWidget != null);

  final String? label;
  final Widget? labelWidget;
  final Widget value;
  final bool labelEmphasized;
  final bool valueEmphasized;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final labelStyle = labelEmphasized
        ? AppTypography.bodyStrong(context).copyWith(color: colors.textPrimary)
        : AppTypography.bodySm(context).copyWith(color: colors.textSecondary);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Expanded(child: labelWidget ?? Text(label!, style: labelStyle)),
        const SizedBox(width: AppSpacing.space4),
        DefaultTextStyle(
          style: valueEmphasized
              ? AppTypography.bodyStrong(context).copyWith(color: valueColor ?? colors.textPrimary)
              : AppTypography.bodySm(context).copyWith(color: valueColor ?? colors.textPrimary),
          child: value,
        ),
      ],
    );
  }
}

class _DashedTopLine extends StatelessWidget {
  const _DashedTopLine();

  @override
  Widget build(BuildContext context) {
    final color = context.appColors.borderDefault;

    return CustomPaint(
      size: const Size(double.infinity, 1),
      painter: _DashedTopLinePainter(color: color),
    );
  }
}

class _DashedTopLinePainter extends CustomPainter {
  const _DashedTopLinePainter({required this.color});

  final Color color;

  static const _dashWidth = 6.0;
  static const _dashGap = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;

    var x = 0.0;
    while (x < size.width) {
      final end = (x + _dashWidth).clamp(0.0, size.width).toDouble();
      canvas.drawLine(Offset(x, 0), Offset(end, 0), paint);
      x += _dashWidth + _dashGap;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedTopLinePainter oldDelegate) => color != oldDelegate.color;
}
