import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/components/app_card.dart';
import 'package:ai_clinic/core/ui/components/app_money_display.dart';
import 'package:ai_clinic/features/billing/domain/discount_kind.dart';
import 'package:ai_clinic/features/billing/domain/invoice_item.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/invoice_detail/invoice_section_title.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/invoice_detail/invoice_totals_panel.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/invoice_perforation_divider.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

/// Raised card hosting line items and invoice-level totals.
class InvoiceLineItemsCard extends StatelessWidget {
  const InvoiceLineItemsCard({
    required this.items,
    required this.currency,
    required this.totals,
    super.key,
  });

  final List<InvoiceItem> items;
  final String currency;
  final InvoiceTotalsModel totals;

  static const _smBreakpoint = 600.0;

  @override
  Widget build(BuildContext context) {
    final hasLineDiscounts = items.any((item) => item.lineDiscountAmount.asDouble > 0);

    return AppCard(
      variant: CardVariant.raised,
      padding: CardPadding.md,
      header: const InvoiceSectionTitle(icon: Icons.receipt_long_outlined, title: 'Line items'),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.x2l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.space5,
                AppSpacing.space4,
                AppSpacing.space5,
                0,
              ),
              child: _LineItemsTable(
                items: items,
                currency: currency,
                hasLineDiscounts: hasLineDiscounts,
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpacing.space5),
              child: InvoicePerforationDivider(),
            ),
            InvoiceTotalsPanel(model: totals),
          ],
        ),
      ),
    );
  }
}

class _LineItemsTable extends StatelessWidget {
  const _LineItemsTable({
    required this.items,
    required this.currency,
    required this.hasLineDiscounts,
  });

  final List<InvoiceItem> items;
  final String currency;
  final bool hasLineDiscounts;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.space4),
        child: Text(
          'No line items',
          style: AppTypography.bodySm(context).copyWith(color: colors.textSecondary),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final showWideColumns = constraints.maxWidth >= InvoiceLineItemsCard._smBreakpoint;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _HeaderRow(showWideColumns: showWideColumns, hasLineDiscounts: hasLineDiscounts),
            for (final item in items) ...[
              Divider(height: 1, color: colors.borderSubtle.withValues(alpha: 0.7)),
              _LineItemRow(
                item: item,
                currency: currency,
                showWideColumns: showWideColumns,
                hasLineDiscounts: hasLineDiscounts,
              ),
            ],
            const SizedBox(height: AppSpacing.space2),
          ],
        );
      },
    );
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({required this.showWideColumns, required this.hasLineDiscounts});

  final bool showWideColumns;
  final bool hasLineDiscounts;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.space2),
      child: Row(
        children: [
          Expanded(child: _HeaderCell('Service')),
          if (showWideColumns) Expanded(child: _HeaderCell('Unit', align: TextAlign.end)),
          const SizedBox(width: 64, child: _HeaderCell('Qty', align: TextAlign.center)),
          if (showWideColumns && hasLineDiscounts)
            Expanded(child: _HeaderCell('Discount', align: TextAlign.end)),
          Expanded(child: _HeaderCell('Amount', align: TextAlign.end)),
        ],
      ),
    );
  }
}

class _LineItemRow extends StatelessWidget {
  const _LineItemRow({
    required this.item,
    required this.currency,
    required this.showWideColumns,
    required this.hasLineDiscounts,
  });

  final InvoiceItem item;
  final String currency;
  final bool showWideColumns;
  final bool hasLineDiscounts;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final discountText = item.lineDiscountAmount.asDouble > 0
        ? DiscountKind.labelFor(item.lineDiscountKind, item.lineDiscountValue)
        : '—';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.space3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(item.description, style: AppTypography.bodySm(context).copyWith(color: colors.textPrimary)),
          ),
          if (showWideColumns)
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: AppMoneyDisplay(amount: item.unitPrice.asDouble, currency: currency),
              ),
            ),
          SizedBox(
            width: 64,
            child: Text(
              item.quantity,
              textAlign: TextAlign.center,
              style: AppTypography.bodySm(context).copyWith(
                color: colors.textSecondary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          if (showWideColumns && hasLineDiscounts)
            Expanded(
              child: Text(
                discountText,
                textAlign: TextAlign.end,
                style: AppTypography.bodySm(context).copyWith(
                  color: colors.statusSuccessFg,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: AppMoneyDisplay(amount: item.lineTotal.asDouble, currency: currency),
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
      style: AppTypography.overline(context).copyWith(
        color: context.appColors.textTertiary,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}
