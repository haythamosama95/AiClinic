import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/components/app_badge.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/features/billing/domain/invoice_status.dart';
import 'package:ai_clinic/features/billing/presentation/utils/billing_formatting.dart';

/// Status badge for invoice list and detail surfaces.
class InvoiceStatusBadge extends StatelessWidget {
  const InvoiceStatusBadge({
    required this.status,
    this.size = BadgeSize.md,
    super.key,
  });

  final InvoiceStatus status;
  final BadgeSize size;

  @override
  Widget build(BuildContext context) {
    final style = statusBadgeStyle(status);
    return AppBadge(
      size: size,
      variant: BadgeVariant.soft,
      color: _badgeColor(style.variant),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(style.icon, size: 12),
          const SizedBox(width: AppSpacing.space1),
          Text(status.label),
        ],
      ),
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
