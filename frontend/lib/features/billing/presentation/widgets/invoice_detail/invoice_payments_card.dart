import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/components/app_card.dart';
import 'package:ai_clinic/core/ui/components/app_button.dart';
import 'package:ai_clinic/core/ui/components/app_empty_state.dart';
import 'package:ai_clinic/core/ui/components/app_money_display.dart';
import 'package:ai_clinic/features/billing/domain/invoice_status.dart';
import 'package:ai_clinic/features/billing/domain/payment.dart';
import 'package:ai_clinic/features/billing/presentation/utils/billing_formatting.dart';
import 'package:ai_clinic/features/billing/presentation/utils/payment_method_l10n.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/invoice_detail/invoice_detail_tooltip.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/invoice_detail/invoice_section_title.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/invoice_detail/invoice_totals_panel.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

/// Raised card hosting the payment ledger and payment totals.
class InvoicePaymentsCard extends StatelessWidget {
  const InvoicePaymentsCard({
    required this.payments,
    required this.currency,
    required this.totals,
    required this.status,
    this.onAddPayment,
    this.canAddPayment = false,
    this.addPaymentTooltip,
    super.key,
  });

  final List<Payment> payments;
  final String currency;
  final InvoiceTotalsModel totals;
  final InvoiceStatus status;
  final VoidCallback? onAddPayment;
  final bool canAddPayment;
  final String? addPaymentTooltip;

  static const _smBreakpoint = 600.0;
  static const _mdBreakpoint = 768.0;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      variant: CardVariant.raised,
      padding: CardPadding.md,
      header: Row(
        children: [
          const Expanded(
            child: InvoiceSectionTitle(icon: Icons.account_balance_wallet_outlined, title: 'Payments'),
          ),
          InvoiceDetailTooltip(
            message: addPaymentTooltip ?? InvoiceDetailActionTooltips.addPaymentMessage(disabledReason: null),
            child: AppButton(
              size: AppButtonSize.sm,
              leadingIcon: const Icon(Icons.add, size: 16),
              disabled: !canAddPayment,
              onPressed: canAddPayment ? onAddPayment : null,
              child: const Text('Add payment'),
            ),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.x2l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (payments.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.space5, AppSpacing.space4, AppSpacing.space5, 0),
                child: _PaymentLedgerTable(payments: payments, currency: currency),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space5, vertical: AppSpacing.space8),
                child: AppEmptyState(
                  variant: AppEmptyStateVariant.firstRun,
                  title: 'No payments yet',
                  description: status == InvoiceStatus.draft
                      ? 'Issue this invoice before recording a payment.'
                      : 'Payments recorded against this invoice will appear here.',
                ),
              ),
            InvoiceTotalsPanel(model: totals),
          ],
        ),
      ),
    );
  }
}

class _PaymentLedgerTable extends StatelessWidget {
  const _PaymentLedgerTable({required this.payments, required this.currency});

  final List<Payment> payments;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return LayoutBuilder(
      builder: (context, constraints) {
        final showRecorded = constraints.maxWidth >= InvoicePaymentsCard._smBreakpoint;
        final showBy = constraints.maxWidth >= InvoicePaymentsCard._mdBreakpoint;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.space2),
              child: Row(
                children: [
                  const Expanded(child: _HeaderCell('Payment')),
                  if (showRecorded) const Expanded(child: _HeaderCell('Recorded', align: TextAlign.end)),
                  if (showBy) const Expanded(child: _HeaderCell('By', align: TextAlign.end)),
                  const Expanded(child: _HeaderCell('Amount', align: TextAlign.end)),
                ],
              ),
            ),
            for (final payment in payments) ...[
              Divider(height: 1, color: colors.borderSubtle.withValues(alpha: 0.7)),
              _PaymentLedgerRow(payment: payment, currency: currency, showRecorded: showRecorded, showBy: showBy),
            ],
            const SizedBox(height: AppSpacing.space2),
          ],
        );
      },
    );
  }
}

class _PaymentLedgerRow extends StatelessWidget {
  const _PaymentLedgerRow({
    required this.payment,
    required this.currency,
    required this.showRecorded,
    required this.showBy,
  });

  final Payment payment;
  final String currency;
  final bool showRecorded;
  final bool showBy;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final amountColor = payment.isRefund ? colors.statusDangerFg : colors.statusSuccessFg;
    final methodLabel = payment.method.labelFor(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.space3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.surfaceMuted,
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(6.5),
                    child: Icon(BillingFormatting.paymentMethodIcon(payment.method), size: 14, color: colors.iconMuted),
                  ),
                ),
                const SizedBox(width: AppSpacing.space2 + AppSpacing.space05),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text.rich(
                        TextSpan(
                          style: AppTypography.bodySm(context).copyWith(color: colors.textPrimary),
                          children: [
                            TextSpan(text: methodLabel),
                            if (payment.isRefund)
                              TextSpan(
                                text: ' · Refund',
                                style: AppTypography.caption(context).copyWith(color: colors.statusDangerFg),
                              ),
                          ],
                        ),
                      ),
                      if (payment.reference?.trim().isNotEmpty == true) ...[
                        const SizedBox(height: AppSpacing.space05),
                        Text(
                          payment.reference!.trim(),
                          style: AppTypography.caption(
                            context,
                          ).copyWith(color: colors.textTertiary, fontFamily: AppTypography.mono(context).fontFamily),
                        ),
                      ],
                      if (payment.note?.trim().isNotEmpty == true) ...[
                        const SizedBox(height: AppSpacing.space05),
                        Text(
                          payment.note!.trim(),
                          style: AppTypography.caption(context).copyWith(color: colors.textSecondary),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (showRecorded)
            Expanded(
              child: Text(
                BillingFormatting.formatDateTime(payment.recordedAt),
                textAlign: TextAlign.end,
                style: AppTypography.bodySm(
                  context,
                ).copyWith(color: colors.textSecondary, fontFeatures: const [FontFeature.tabularFigures()]),
              ),
            ),
          if (showBy)
            Expanded(
              child: Text(
                payment.recordedByDisplayName ?? '—',
                textAlign: TextAlign.end,
                style: AppTypography.bodySm(context).copyWith(color: colors.textSecondary),
              ),
            ),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: DefaultTextStyle(
                style: AppTypography.bodySm(context).copyWith(color: amountColor),
                child: AppMoneyDisplay(amount: payment.amount.asDouble, currency: currency, negative: payment.isRefund),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell(this.label, {this.align = TextAlign.start});

  final String label;
  final TextAlign align;

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      textAlign: align,
      style: AppTypography.overline(
        context,
      ).copyWith(color: context.appColors.textTertiary, fontWeight: FontWeight.w500),
    );
  }
}
