import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';

import 'package:ai_clinic/core/money/money.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/billing/domain/visit_billing_models.dart';

bool visitInvoiceFixedDiscountExceedsSubtotal({
  required VisitBillingDiscountType discountType,
  required Decimal discountValue,
  required Money subtotal,
}) {
  return discountType == VisitBillingDiscountType.fixed &&
      discountValue > Decimal.zero &&
      Money.parse(discountValue.toString()).compareTo(subtotal) > 0;
}

/// Editable discount sidebar for the visit-billing review step.
class VisitInvoiceDiscountSidebar extends StatelessWidget {
  const VisitInvoiceDiscountSidebar({
    required this.discountType,
    required this.discountValue,
    required this.subtotal,
    required this.currency,
    required this.onDiscountTypeChanged,
    required this.onDiscountValueChanged,
    super.key,
  });

  final VisitBillingDiscountType discountType;
  final Decimal discountValue;
  final Money subtotal;
  final String currency;
  final ValueChanged<VisitBillingDiscountType> onDiscountTypeChanged;
  final ValueChanged<String> onDiscountValueChanged;

  bool get _fixedDiscountExceedsSubtotal => visitInvoiceFixedDiscountExceedsSubtotal(
    discountType: discountType,
    discountValue: discountValue,
    subtotal: subtotal,
  );

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          variant: CardVariant.raised,
          padding: CardPadding.lg,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColorPrimitives.amber50,
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.space2 + 2),
                      child: Icon(
                        Icons.percent_rounded,
                        size: 18,
                        color: AppColorPrimitives.amber700,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.space3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Discount',
                          style: AppTypography.overline(
                            context,
                          ).copyWith(color: colors.textTertiary),
                        ),
                        Text(
                          'Optional adjustment',
                          style: AppTypography.bodySm(
                            context,
                          ).copyWith(color: colors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.space5),
              DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: colors.borderSubtle)),
                ),
                child: Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.space5),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AppFormField(
                        id: 'discount-type',
                        label: 'Discount type',
                        child: AppRadioGroup(
                          value: discountType.name,
                          onChanged: (value) => onDiscountTypeChanged(
                            VisitBillingDiscountType.values.byName(value),
                          ),
                          options: const [
                            AppRadioOption(value: 'none', label: 'No discount'),
                            AppRadioOption(
                              value: 'percentage',
                              label: 'Percentage off',
                            ),
                            AppRadioOption(
                              value: 'fixed',
                              label: 'Fixed amount off',
                            ),
                          ],
                        ),
                      ),
                      if (discountType ==
                          VisitBillingDiscountType.percentage) ...[
                        const SizedBox(height: AppSpacing.space4),
                        AppFormField(
                          id: 'discount-percent',
                          label: 'Percentage',
                          helperText: 'Applied to subtotal before tax',
                          child: AppNumberInput(
                            min: 0,
                            max: 100,
                            step: 1,
                            placeholder: '0',
                            initialValue: discountValue > Decimal.zero
                                ? discountValue.toDouble()
                                : null,
                            onValueChange: (value) => onDiscountValueChanged(
                              value?.toString() ?? '0',
                            ),
                          ),
                        ),
                      ],
                      if (discountType == VisitBillingDiscountType.fixed) ...[
                        const SizedBox(height: AppSpacing.space4),
                        AppFormField(
                          id: 'discount-fixed',
                          label: 'Amount off',
                          child: AppMoneyField(
                            currency: currency,
                            placeholder: '0.00',
                            invalid: _fixedDiscountExceedsSubtotal,
                            initialValue: discountValue > Decimal.zero
                                ? discountValue.toDouble()
                                : null,
                            onValueChange: (value) => onDiscountValueChanged(
                              value?.toStringAsFixed(2) ?? '0',
                            ),
                          ),
                        ),
                        if (_fixedDiscountExceedsSubtotal) ...[
                          const SizedBox(height: AppSpacing.space3),
                          const AppAlert(
                            variant: AppAlertVariant.warning,
                            title: 'Amount exceeds invoice subtotal',
                            child: Text(
                              'The discount will be capped at the subtotal.',
                            ),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.space4),
        const VisitInvoiceDiscountInfoCard(),
      ],
    );
  }
}

class VisitInvoiceDiscountInfoCard extends StatelessWidget {
  const VisitInvoiceDiscountInfoCard({this.message, super.key});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return AppCard(
      variant: CardVariant.flat,
      padding: CardPadding.md,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.receipt_long_outlined, size: 16, color: colors.iconMuted),
          const SizedBox(width: AppSpacing.space3),
          Expanded(
            child: Text(
              message ??
                  'Finalizing issues the invoice linked to this visit. Payment can be recorded from the patient billing tab.',
              style: AppTypography.caption(
                context,
              ).copyWith(color: colors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

/// Read-only discount summary for issued invoices.
class VisitInvoiceReadOnlyDiscountSidebar extends StatelessWidget {
  const VisitInvoiceReadOnlyDiscountSidebar({
    required this.discountType,
    required this.discountValue,
    required this.discountAmount,
    required this.currency,
    super.key,
  });

  final VisitBillingDiscountType discountType;
  final Decimal discountValue;
  final Money discountAmount;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    if (!discountAmount.isPositive) {
      return const VisitInvoiceDiscountInfoCard(
        message: 'No discount was applied to this invoice.',
      );
    }

    final discountLabel = switch (discountType) {
      VisitBillingDiscountType.percentage =>
        'Percentage off (${_discountPercentLabel(discountValue)})',
      VisitBillingDiscountType.fixed => 'Fixed amount off',
      VisitBillingDiscountType.none => 'Discount',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          variant: CardVariant.raised,
          padding: CardPadding.lg,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColorPrimitives.amber50,
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.space2 + 2),
                      child: Icon(
                        Icons.percent_rounded,
                        size: 18,
                        color: AppColorPrimitives.amber700,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.space3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Discount',
                          style: AppTypography.overline(
                            context,
                          ).copyWith(color: colors.textTertiary),
                        ),
                        Text(
                          'Applied adjustment',
                          style: AppTypography.bodySm(
                            context,
                          ).copyWith(color: colors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.space5),
              DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: colors.borderSubtle)),
                ),
                child: Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.space5),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Discount type',
                        style: AppTypography.caption(
                          context,
                        ).copyWith(color: colors.textTertiary),
                      ),
                      const SizedBox(height: AppSpacing.space1),
                      Text(
                        discountLabel,
                        style: AppTypography.bodySm(
                          context,
                        ).copyWith(color: colors.textPrimary),
                      ),
                      const SizedBox(height: AppSpacing.space4),
                      Text(
                        'Amount',
                        style: AppTypography.caption(
                          context,
                        ).copyWith(color: colors.textTertiary),
                      ),
                      const SizedBox(height: AppSpacing.space1),
                      AppMoneyDisplay(
                        amount: discountAmount,
                        currency: currency,
                        negative: true,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.space4),
        const VisitInvoiceDiscountInfoCard(
          message:
              'This invoice has been finalized. Payment can be recorded from the patient billing tab.',
        ),
      ],
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
