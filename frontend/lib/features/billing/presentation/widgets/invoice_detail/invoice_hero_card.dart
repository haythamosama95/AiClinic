import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/components/app_avatar.dart';
import 'package:ai_clinic/core/ui/components/app_badge.dart';
import 'package:ai_clinic/core/ui/components/app_button.dart';
import 'package:ai_clinic/core/ui/components/app_card.dart';
import 'package:ai_clinic/core/ui/components/app_money_display.dart';
import 'package:ai_clinic/features/billing/domain/invoice_detail.dart';
import 'package:ai_clinic/features/billing/domain/money.dart';
import 'package:ai_clinic/features/billing/presentation/utils/billing_formatting.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/invoice_detail/invoice_meta_grid.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/invoice_detail/invoice_detail_tooltip.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/invoice_status_badge.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

/// Raised hero card for the invoice detail page.
class InvoiceHeroCard extends StatelessWidget {
  const InvoiceHeroCard({
    required this.invoice,
    required this.patientName,
    required this.balance,
    required this.onPatientTap,
    this.mrn,
    this.branchName,
    this.onVoid,
    this.onPrint,
    this.canVoid = false,
    this.voidTooltip,
    this.printTooltip = InvoiceDetailActionTooltips.printMessage,
    super.key,
  });

  final InvoiceDetail invoice;
  final String patientName;
  final String? mrn;
  final String? branchName;
  final Money balance;
  final VoidCallback onPatientTap;
  final VoidCallback? onVoid;
  final VoidCallback? onPrint;
  final bool canVoid;
  final String? voidTooltip;
  final String printTooltip;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final displayNumber = BillingFormatting.invoiceDisplayNumber(invoice.invoiceNumber, invoice.id);
    final isVoided = invoice.status.isVoided;
    final balanceLabel = isVoided ? 'Balance at void' : 'Balance due';
    final balanceColor = !isVoided && balance.asDouble <= 0 ? colors.statusSuccessFg : colors.textPrimary;
    final mrnDisplay = mrn?.trim().isNotEmpty == true ? mrn!.trim() : '—';

    return AppCard(
      variant: CardVariant.raised,
      padding: CardPadding.lg,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppAvatar(name: patientName, size: AvatarSize.lg),
                      const SizedBox(width: AppSpacing.space4),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Wrap(
                              spacing: AppSpacing.space2,
                              runSpacing: AppSpacing.space2,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  displayNumber,
                                  style: AppTypography.mono(context).copyWith(
                                    fontSize: AppTypography.h1(context).fontSize,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.02,
                                    color: colors.textPrimary,
                                    fontFeatures: const [FontFeature.tabularFigures()],
                                  ),
                                ),
                                InvoiceStatusBadge(status: invoice.status, size: BadgeSize.md),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.space2),
                            Text.rich(
                              TextSpan(
                                style: AppTypography.body(context).copyWith(color: colors.textSecondary),
                                children: [
                                  const TextSpan(text: 'Billed to '),
                                  WidgetSpan(
                                    alignment: PlaceholderAlignment.baseline,
                                    baseline: TextBaseline.alphabetic,
                                    child: Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        onTap: onPatientTap,
                                        borderRadius: BorderRadius.circular(AppRadius.sm),
                                        child: Text(
                                          patientName,
                                          style: AppTypography.body(
                                            context,
                                          ).copyWith(color: colors.textLink, fontWeight: FontWeight.w500),
                                        ),
                                      ),
                                    ),
                                  ),
                                  TextSpan(
                                    text: ' · $mrnDisplay',
                                    style: AppTypography.caption(context).copyWith(
                                      color: colors.textTertiary,
                                      fontFeatures: const [FontFeature.tabularFigures()],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.space4),
                  InvoiceMetaGrid(
                    items: [
                      InvoiceMetaItem(
                        label: 'Branch',
                        icon: Icons.apartment_outlined,
                        value: branchName?.trim().isNotEmpty == true ? branchName!.trim() : '—',
                      ),
                      InvoiceMetaItem(label: 'Created', value: BillingFormatting.formatDate(invoice.createdAt)),
                      InvoiceMetaItem(
                        label: 'Issued',
                        value: invoice.issuedAt == null
                            ? 'Not yet issued'
                            : BillingFormatting.formatDate(invoice.issuedAt!),
                      ),
                      InvoiceMetaItem(
                        label: 'Updated',
                        icon: Icons.update_outlined,
                        value: BillingFormatting.formatDateTime(invoice.updatedAt),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.space4),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InvoiceDetailTooltip(
                      message: voidTooltip ?? InvoiceDetailActionTooltips.voidMessage(disabledReason: null),
                      child: AppButton(
                        variant: AppButtonVariant.danger,
                        size: AppButtonSize.sm,
                        leadingIcon: const Icon(Icons.delete_outline, size: 16),
                        disabled: !canVoid,
                        onPressed: canVoid ? onVoid : null,
                        child: const Text('Void'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.space2),
                    InvoiceDetailTooltip(
                      message: printTooltip,
                      child: AppButton(
                        size: AppButtonSize.sm,
                        leadingIcon: const Icon(Icons.print_outlined, size: 16),
                        onPressed: onPrint,
                        child: const Text('Print'),
                      ),
                    ),
                  ],
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(balanceLabel, style: AppTypography.overline(context).copyWith(color: colors.textTertiary)),
                      AppMoneyDisplay(
                        amount: balance.asDouble,
                        currency: invoice.currency,
                        emphasis: true,
                        negative: balance.isNegative,
                        style: AppTypography.h1(
                          context,
                        ).copyWith(color: balanceColor, fontFeatures: const [FontFeature.tabularFigures()]),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
