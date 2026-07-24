import 'package:flutter/material.dart';

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

/// Responsive 2-up → 4-up meta grid for the invoice hero card.
class InvoiceMetaGrid extends StatelessWidget {
  const InvoiceMetaGrid({required this.items, super.key});

  final List<InvoiceMetaItem> items;

  static const _smBreakpoint = 600.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= _smBreakpoint;
        final itemWidth = isWide
            ? (constraints.maxWidth - AppSpacing.space4 * 3) / 4
            : (constraints.maxWidth - AppSpacing.space4) / 2;

        return Wrap(
          spacing: AppSpacing.space4,
          runSpacing: AppSpacing.space4,
          children: [
            for (final item in items)
              SizedBox(
                width: itemWidth.clamp(0, constraints.maxWidth),
                child: _MetaItem(item: item),
              ),
          ],
        );
      },
    );
  }
}

class _MetaItem extends StatelessWidget {
  const _MetaItem({required this.item});

  final InvoiceMetaItem item;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          item.label,
          style: AppTypography.overline(
            context,
          ).copyWith(color: colors.textTertiary),
        ),
        const SizedBox(height: AppSpacing.space1),
        DefaultTextStyle(
          style: AppTypography.bodySm(context),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          child: item.icon == null
              ? Text(item.value)
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(item.icon, size: 14, color: colors.iconMuted),
                    const SizedBox(width: 6),
                    Flexible(child: Text(item.value)),
                  ],
                ),
        ),
      ],
    );
  }
}
