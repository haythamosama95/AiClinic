import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/components/app_money_display.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/billing/domain/invoice_detail.dart';
import 'package:ai_clinic/features/billing/domain/invoice_item.dart';
import 'package:ai_clinic/features/billing/domain/money.dart';
import 'package:ai_clinic/features/billing/presentation/providers/organization_currency_provider.dart';
import 'package:ai_clinic/features/billing/presentation/utils/billing_formatting.dart';
import 'package:ai_clinic/features/billing/domain/visit_billing_models.dart';

/// Read-only invoice summary for visit billing contexts.
class VisitInvoiceSummaryPanel extends ConsumerWidget {
  const VisitInvoiceSummaryPanel({this.invoice, this.preview, this.expanded = false, super.key})
    : assert(invoice != null || preview != null);

  final InvoiceDetail? invoice;
  final VisitBillingInvoicePreview? preview;
  final bool expanded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final currency = ref.watch(organizationCurrencyProvider);

    if (invoice != null) {
      return _InvoiceDetailSummary(invoice: invoice!, expanded: expanded, colors: colors);
    }

    return _PreviewSummary(preview: preview!, colors: colors, currency: currency);
  }
}

class _InvoiceDetailSummary extends StatelessWidget {
  const _InvoiceDetailSummary({required this.invoice, required this.expanded, required this.colors});

  final InvoiceDetail invoice;
  final bool expanded;
  final AppSemanticColors colors;

  @override
  Widget build(BuildContext context) {
    final badgeStyle = statusBadgeStyle(invoice.status);
    final displayNumber = BillingFormatting.invoiceDisplayNumber(invoice.invoiceNumber, invoice.id);
    final netTotal = invoice.subtotal - invoice.discountAmount;
    final hasDiscount = !invoice.discountAmount.isZero;
    final showBalance = !invoice.status.isDraft && invoice.balance.isPositive;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceSunken.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.space4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.receipt_long_outlined, size: 16, color: colors.iconMuted),
                const SizedBox(width: AppSpacing.space2),
                Expanded(
                  child: Text(
                    displayNumber,
                    style: AppTypography.caption(
                      context,
                    ).copyWith(color: colors.textSecondary, fontFamily: 'monospace', letterSpacing: 0.8),
                  ),
                ),
                AppBadge(
                  size: BadgeSize.sm,
                  variant: BadgeVariant.soft,
                  color: _badgeColor(badgeStyle.variant),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(badgeStyle.icon, size: 12),
                      const SizedBox(width: AppSpacing.space1),
                      Text(invoice.status.label),
                    ],
                  ),
                ),
              ],
            ),
            if (expanded && invoice.items.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.space4),
              const Divider(height: 1),
              const SizedBox(height: AppSpacing.space3),
              for (final item in invoice.items) ...[
                _LineItemRow(item: item, currency: invoice.currency),
                if (item != invoice.items.last) const SizedBox(height: AppSpacing.space3),
              ],
              const SizedBox(height: AppSpacing.space4),
              const Divider(height: 1),
              const SizedBox(height: AppSpacing.space3),
              _AmountRow(label: 'Subtotal', amount: invoice.subtotal, currency: invoice.currency),
              if (hasDiscount) ...[
                const SizedBox(height: AppSpacing.space2),
                _AmountRow(
                  label: 'Discount',
                  amount: invoice.discountAmount,
                  currency: invoice.currency,
                  negative: true,
                ),
              ],
              const SizedBox(height: AppSpacing.space2),
              _AmountRow(label: 'Total', amount: netTotal, currency: invoice.currency, emphasis: true),
              if (showBalance) ...[
                const SizedBox(height: AppSpacing.space2),
                _AmountRow(label: 'Balance due', amount: invoice.balance, currency: invoice.currency),
              ],
            ] else ...[
              const SizedBox(height: AppSpacing.space3),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${invoice.items.length} service${invoice.items.length == 1 ? '' : 's'}${hasDiscount ? ' · Discount applied' : ''}',
                      style: AppTypography.bodySm(context).copyWith(color: colors.textSecondary),
                    ),
                  ),
                  AppMoneyDisplay(amount: netTotal.asDouble, currency: invoice.currency, emphasis: true),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PreviewSummary extends StatelessWidget {
  const _PreviewSummary({required this.preview, required this.colors, required this.currency});

  final VisitBillingInvoicePreview preview;
  final AppSemanticColors colors;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final hasDiscount = preview.discountAmount > 0;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceSunken.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.space4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.receipt_long_outlined, size: 16, color: colors.iconMuted),
                const SizedBox(width: AppSpacing.space2),
                Expanded(
                  child: Text(
                    preview.number,
                    style: AppTypography.caption(
                      context,
                    ).copyWith(color: colors.textSecondary, fontFamily: 'monospace', letterSpacing: 0.8),
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.statusWarningSurface,
                    borderRadius: BorderRadius.circular(AppRadius.full),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space2 + 2, vertical: 2),
                    child: Text(
                      'Draft',
                      style: AppTypography.caption(
                        context,
                      ).copyWith(color: colors.statusWarningFg, fontWeight: FontWeight.w500),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.space3),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${preview.lines.length} service${preview.lines.length == 1 ? '' : 's'}${hasDiscount ? ' · Discount applied' : ''}',
                    style: AppTypography.bodySm(context).copyWith(color: colors.textSecondary),
                  ),
                ),
                AppMoneyDisplay(amount: preview.total, currency: currency, emphasis: true),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LineItemRow extends StatelessWidget {
  const _LineItemRow({required this.item, required this.currency});

  final InvoiceItem item;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.description, style: AppTypography.bodySm(context).copyWith(color: colors.textPrimary)),
              const SizedBox(height: 2),
              Text('Qty ${item.quantity}', style: AppTypography.caption(context).copyWith(color: colors.textTertiary)),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.space3),
        AppMoneyDisplay(amount: item.lineTotal.asDouble, currency: currency),
      ],
    );
  }
}

class _AmountRow extends StatelessWidget {
  const _AmountRow({
    required this.label,
    required this.amount,
    required this.currency,
    this.emphasis = false,
    this.negative = false,
  });

  final String label;
  final Money amount;
  final String currency;
  final bool emphasis;
  final bool negative;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: (emphasis ? AppTypography.bodyStrong(context) : AppTypography.bodySm(context)).copyWith(
              color: emphasis ? colors.textPrimary : colors.textSecondary,
            ),
          ),
        ),
        AppMoneyDisplay(
          amount: amount.asDouble,
          currency: currency,
          emphasis: emphasis,
          negative: negative ? true : null,
        ),
      ],
    );
  }
}

BadgeColor _badgeColor(InvoiceStatusBadgeVariant variant) {
  return switch (variant) {
    InvoiceStatusBadgeVariant.muted => BadgeColor.neutral,
    InvoiceStatusBadgeVariant.primary => BadgeColor.teal,
    InvoiceStatusBadgeVariant.accent => BadgeColor.warning,
    InvoiceStatusBadgeVariant.success => BadgeColor.success,
    InvoiceStatusBadgeVariant.destructive => BadgeColor.danger,
  };
}
