import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/features/billing/domain/invoice_status.dart';
import 'package:ai_clinic/features/billing/presentation/utils/billing_formatting.dart';

/// Status pill for invoice list and detail surfaces.
class InvoiceStatusBadge extends StatelessWidget {
  const InvoiceStatusBadge({
    required this.status,
    this.dense = false,
    super.key,
  });

  final InvoiceStatus status;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final style = statusBadgeStyle(status);
    final color = switch (style.variant) {
      InvoiceStatusBadgeVariant.muted => AppBadgeColor.neutral,
      InvoiceStatusBadgeVariant.primary => AppBadgeColor.info,
      InvoiceStatusBadgeVariant.accent => AppBadgeColor.warning,
      InvoiceStatusBadgeVariant.success => AppBadgeColor.success,
      InvoiceStatusBadgeVariant.destructive => AppBadgeColor.danger,
    };

    final label = Text(status.label);
    if (dense) {
      return AppBadge(color: color, size: AppBadgeSize.sm, child: label);
    }

    return AppBadge(
      color: color,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(style.icon, size: 14),
          const SizedBox(width: AppSpacing.s1),
          label,
        ],
      ),
    );
  }
}
