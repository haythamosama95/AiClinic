import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/billing/domain/invoice_status.dart';
import 'package:ai_clinic/features/billing/presentation/utils/billing_formatting.dart';

/// Status badge for invoice surfaces (V1-6).
class InvoiceStatusBadge extends StatelessWidget {
  const InvoiceStatusBadge({
    required this.status,
    this.size = BadgeSize.sm,
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
          Icon(style.icon, size: size == BadgeSize.sm ? 12 : 14),
          const SizedBox(width: AppSpacing.space1),
          Text(status.label),
        ],
      ),
    );
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
}
