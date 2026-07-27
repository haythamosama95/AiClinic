import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/components/app_badge.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

/// A single label + value tile in [InvoiceMetaGrid].
class InvoiceMetaItem {
  const InvoiceMetaItem({required this.label, required this.value, this.icon});

  final String label;
  final String value;
  final IconData? icon;
}

/// Horizontal wrap of meta badges for the invoice hero card.
class InvoiceMetaGrid extends StatelessWidget {
  const InvoiceMetaGrid({required this.items, super.key});

  final List<InvoiceMetaItem> items;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.space2,
      runSpacing: AppSpacing.space2,
      children: [for (final item in items) _MetaBadgeChip(item: item)],
    );
  }
}

class _MetaBadgeChip extends StatelessWidget {
  const _MetaBadgeChip({required this.item});

  final InvoiceMetaItem item;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isPendingIssue = item.label == 'Issued' && item.value == 'Not yet issued';

    return AppBadge(
      size: BadgeSize.md,
      variant: BadgeVariant.soft,
      color: isPendingIssue ? BadgeColor.warning : BadgeColor.neutral,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (item.icon != null) ...[
            Icon(item.icon, size: 14, color: colors.iconMuted),
            const SizedBox(width: AppSpacing.space1),
          ],
          Text.rich(
            TextSpan(
              style: AppTypography.bodySm(context),
              children: [
                TextSpan(
                  text: '${item.label} · ',
                  style: TextStyle(color: colors.textTertiary, fontWeight: FontWeight.w500),
                ),
                TextSpan(
                  text: item.value,
                  style: TextStyle(color: colors.textSecondary),
                ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
