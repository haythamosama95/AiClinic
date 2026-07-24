import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/features/billing/domain/invoice_detail.dart';
import 'package:ai_clinic/features/billing/presentation/utils/billing_formatting.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

/// Danger-surface notice shown when an invoice has been voided.
class InvoiceVoidedNotice extends StatelessWidget {
  const InvoiceVoidedNotice({required this.invoice, super.key});

  final InvoiceDetail invoice;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final voidedAt = invoice.voidedAt ?? invoice.updatedAt;
    final voidedBy = invoice.voidedByName?.trim();
    final auditLine = voidedBy != null && voidedBy.isNotEmpty
        ? '${BillingFormatting.formatDateTime(voidedAt)} · $voidedBy'
        : BillingFormatting.formatDateTime(voidedAt);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.statusDangerSurface,
        border: Border.all(color: colors.statusDangerBorder),
        borderRadius: BorderRadius.circular(AppRadius.x2l),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.space6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: colors.surfaceDefault,
                shape: BoxShape.circle,
              ),
              child: SizedBox(
                width: 36,
                height: 36,
                child: Icon(Icons.warning_amber_outlined, size: 16, color: colors.statusDangerFg),
              ),
            ),
            const SizedBox(width: AppSpacing.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'This invoice was voided',
                    style: AppTypography.bodyStrong(context).copyWith(color: colors.statusDangerFg),
                  ),
                  if (invoice.voidReason?.trim().isNotEmpty == true) ...[
                    const SizedBox(height: AppSpacing.space1),
                    Text(
                      invoice.voidReason!.trim(),
                      style: AppTypography.bodySm(context).copyWith(color: colors.textPrimary),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.space1),
                  Text(
                    auditLine,
                    style: AppTypography.caption(context).copyWith(color: colors.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
