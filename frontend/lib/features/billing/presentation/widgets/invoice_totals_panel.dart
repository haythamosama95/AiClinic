import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/features/billing/domain/invoice_detail.dart';
import 'package:ai_clinic/features/billing/domain/money.dart';
import 'package:ai_clinic/features/billing/presentation/utils/billing_formatting.dart';

/// Subtotal, discounts, insurance, balance summary panel (V1-6).
class InvoiceTotalsPanel extends StatelessWidget {
  const InvoiceTotalsPanel({required this.invoice, super.key});

  final InvoiceDetail invoice;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final theme = Theme.of(context);
    final currency = invoice.currency;
    final paidTotal = invoice.payments.fold<Money>(Money.zero, (sum, payment) => sum + payment.amount);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.muted.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(SpacingTokens.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _TotalRow(
              label: 'Subtotal',
              value: BillingFormatting.formatMoney(invoice.subtotal, currency: currency),
            ),
            if (!invoice.discountAmount.isZero)
              _TotalRow(
                label: 'Discount',
                value: '-${BillingFormatting.formatMoney(invoice.discountAmount, currency: currency)}',
                valueColor: colors.destructive,
              ),
            if (!invoice.insuranceCoveredAmount.isZero)
              _TotalRow(
                label: invoice.insuranceProviderName ?? 'Insurance covered',
                value: '-${BillingFormatting.formatMoney(invoice.insuranceCoveredAmount, currency: currency)}',
              ),
            if (!paidTotal.isZero) ...[
              const Divider(height: SpacingTokens.lg),
              _TotalRow(
                label: 'Paid',
                value: BillingFormatting.formatMoney(paidTotal, currency: currency),
              ),
            ],
            const Divider(height: SpacingTokens.lg),
            Row(
              children: [
                Text(
                  'Balance due',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600, color: colors.foreground),
                ),
                const Spacer(),
                Text(
                  BillingFormatting.formatMoney(invoice.balance, currency: currency),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: invoice.balance.isZero ? const Color(0xFF166534) : colors.foreground,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({required this.label, required this.value, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: colors.mutedForeground)),
          ),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: valueColor ?? colors.foreground,
              fontWeight: FontWeight.w500,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
