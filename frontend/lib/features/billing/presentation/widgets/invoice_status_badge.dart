import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/features/billing/domain/invoice_status.dart';
import 'package:ai_clinic/features/billing/presentation/utils/billing_formatting.dart';

/// Status chip for invoice list and detail headers (V1-6).
class InvoiceStatusBadge extends StatelessWidget {
  const InvoiceStatusBadge({required this.status, this.dense = false, super.key});

  final InvoiceStatus status;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final style = statusBadgeStyle(status);
    final (background, foreground, border) = _colorsFor(style.variant, colors);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: border),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: dense ? 8 : 10, vertical: dense ? 3 : 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(style.icon, size: dense ? 12 : 14, color: foreground),
            const SizedBox(width: 4),
            Text(
              status.label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: foreground,
                fontWeight: FontWeight.w600,
                fontSize: dense ? 11 : 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  (Color, Color, Color) _colorsFor(InvoiceStatusBadgeVariant variant, SemanticColors colors) {
    return switch (variant) {
      InvoiceStatusBadgeVariant.muted => (colors.muted, colors.mutedForeground, colors.border),
      InvoiceStatusBadgeVariant.primary => (
        colors.primary.withValues(alpha: 0.12),
        colors.primary,
        colors.primary.withValues(alpha: 0.35),
      ),
      InvoiceStatusBadgeVariant.accent => (
        colors.accent.withValues(alpha: 0.15),
        colors.accentForeground,
        colors.accent.withValues(alpha: 0.4),
      ),
      InvoiceStatusBadgeVariant.success => (const Color(0xFFDCFCE7), const Color(0xFF166534), const Color(0xFF86EFAC)),
      InvoiceStatusBadgeVariant.destructive => (
        colors.destructive.withValues(alpha: 0.12),
        colors.destructive,
        colors.destructive.withValues(alpha: 0.35),
      ),
    };
  }
}
