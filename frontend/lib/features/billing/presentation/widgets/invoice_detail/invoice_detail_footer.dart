import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/components/app_card.dart';
import 'package:ai_clinic/features/billing/presentation/utils/billing_formatting.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

/// Trailing caption card on the invoice detail page.
class InvoiceDetailFooter extends StatelessWidget {
  const InvoiceDetailFooter({required this.updatedAt, super.key});

  final DateTime updatedAt;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final timestamp = BillingFormatting.formatDateTime(updatedAt);

    return AppCard(
      variant: CardVariant.flat,
      padding: CardPadding.md,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.space05),
            child: Icon(Icons.event_available_outlined, size: 16, color: colors.iconMuted),
          ),
          const SizedBox(width: AppSpacing.space3),
          Expanded(
            child: Text(
              'Last updated $timestamp. Every invoice is tied to exactly one completed visit — '
              'the balance above is recomputed from the line items, discounts, insurance coverage, '
              'and payment ledger shown here.',
              style: AppTypography.caption(context).copyWith(color: colors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
