import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/features/billing/domain/invoice_detail.dart';
import 'package:ai_clinic/features/billing/domain/money.dart';

/// Read-only invoice totals breakdown for detail and editor surfaces.
class InvoiceTotalsPanel extends StatelessWidget {
  const InvoiceTotalsPanel({
    required this.invoice,
    this.emphasizeBalance = true,
    super.key,
  });

  final InvoiceDetail invoice;
  final bool emphasizeBalance;

  Money get _netAfterDiscount => invoice.subtotal - invoice.discountAmount;

  Money get _patientDue => _netAfterDiscount - invoice.insuranceCoveredAmount;

  @override
  Widget build(BuildContext context) {
    final typography = context.typography;
    final colors = context.colors;

    return AppCard(
      variant: AppCardVariant.flat,
      padding: AppCardPadding.sm,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TotalRow(
            label: 'Subtotal',
            amount: invoice.subtotal,
            currency: invoice.currency,
          ),
          if (!invoice.discountAmount.isZero)
            _TotalRow(
              label: 'Discount',
              amount: invoice.discountAmount,
              currency: invoice.currency,
              negative: true,
            ),
          if (!invoice.insuranceCoveredAmount.isZero) ...[
            _TotalRow(
              label: 'Insurance covered',
              amount: invoice.insuranceCoveredAmount,
              currency: invoice.currency,
            ),
            _TotalRow(
              label: 'Patient due',
              amount: _patientDue,
              currency: invoice.currency,
            ),
          ],
          Divider(height: 1, color: colors.borderSubtle),
          const SizedBox(height: AppSpacing.s2),
          _TotalRow(
            label: 'Balance due',
            amount: invoice.balance,
            currency: invoice.currency,
            emphasized: emphasizeBalance,
          ),
          if (emphasizeBalance)
            Padding(
              padding: const EdgeInsetsDirectional.only(top: AppSpacing.s1),
              child: Text(
                'Currency: ${invoice.currency}',
                style: typography.caption.copyWith(color: colors.textTertiary),
              ),
            ),
        ],
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({
    required this.label,
    required this.amount,
    required this.currency,
    this.emphasized = false,
    this.negative = false,
  });

  final String label;
  final Money amount;
  final String currency;
  final bool emphasized;
  final bool negative;

  @override
  Widget build(BuildContext context) {
    final typography = context.typography;
    final decimal = Decimal.parse(amount.wireValue);

    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(vertical: AppSpacing.s1),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: emphasized
                  ? typography.bodyStrong.copyWith(color: context.colors.textPrimary)
                  : typography.body.copyWith(color: context.colors.textSecondary),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          AppMoney(
            amount: decimal,
            currency: currency,
            emphasis: emphasized ? AppMoneyEmphasis.strong : AppMoneyEmphasis.normal,
            negative: negative,
          ),
        ],
      ),
    );
  }
}
