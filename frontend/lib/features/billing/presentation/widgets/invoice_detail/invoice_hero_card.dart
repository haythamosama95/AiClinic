import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/components/app_avatar.dart';
import 'package:ai_clinic/core/ui/components/app_badge.dart';
import 'package:ai_clinic/core/ui/components/app_card.dart';
import 'package:ai_clinic/core/ui/components/app_money_display.dart';
import 'package:ai_clinic/features/billing/domain/invoice_detail.dart';
import 'package:ai_clinic/features/billing/domain/money.dart';
import 'package:ai_clinic/features/billing/presentation/utils/billing_formatting.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/invoice_detail/invoice_meta_grid.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/invoice_status_badge.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

/// Raised perforated hero card for the invoice detail page.
class InvoiceHeroCard extends StatelessWidget {
  const InvoiceHeroCard({
    required this.invoice,
    required this.patientName,
    required this.balance,
    required this.onPatientTap,
    this.mrn,
    this.branchName,
    this.insuranceProviderName,
    this.actions,
    super.key,
  });

  final InvoiceDetail invoice;
  final String patientName;
  final String? mrn;
  final String? branchName;
  final String? insuranceProviderName;
  final Money balance;
  final VoidCallback onPatientTap;
  final Widget? actions;

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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.x2l),
        child: Stack(
          children: [
            const Positioned(top: 0, left: 0, right: 0, child: _PerforatedEdge()),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.space6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final titleBlock = Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AppAvatar(name: patientName, size: AvatarSize.lg),
                          const SizedBox(width: AppSpacing.space4),
                          Flexible(
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
                                              style: AppTypography.body(context).copyWith(
                                                color: colors.textLink,
                                                fontWeight: FontWeight.w500,
                                              ),
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
                      );

                      final balanceBlock = Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            balanceLabel,
                            style: AppTypography.overline(context).copyWith(color: colors.textTertiary),
                          ),
                          DefaultTextStyle(
                            style: AppTypography.display(context).copyWith(
                              color: balanceColor,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                            child: AppMoneyDisplay(
                              amount: balance.asDouble,
                              currency: invoice.currency,
                              emphasis: true,
                              negative: balance.isNegative,
                            ),
                          ),
                        ],
                      );

                      if (constraints.maxWidth < 600) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            titleBlock,
                            const SizedBox(height: AppSpacing.space4),
                            balanceBlock,
                            if (actions != null) ...[
                              const SizedBox(height: AppSpacing.space2),
                              actions!,
                            ],
                          ],
                        );
                      }

                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Flexible(child: titleBlock),
                          const Spacer(),
                          balanceBlock,
                          if (actions != null) ...[
                            const SizedBox(width: AppSpacing.space2),
                            actions!,
                          ],
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: AppSpacing.space5),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border(top: BorderSide(color: colors.borderSubtle)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.space4),
                      child: InvoiceMetaGrid(
                        items: [
                          InvoiceMetaItem(
                            label: 'Branch',
                            icon: Icons.apartment_outlined,
                            value: branchName?.trim().isNotEmpty == true ? branchName!.trim() : '—',
                          ),
                          InvoiceMetaItem(
                            label: 'Created',
                            value: BillingFormatting.formatDate(invoice.createdAt),
                          ),
                          InvoiceMetaItem(
                            label: 'Issued',
                            value: invoice.issuedAt == null
                                ? 'Not yet issued'
                                : BillingFormatting.formatDate(invoice.issuedAt!),
                          ),
                          InvoiceMetaItem(
                            label: 'Insurance',
                            icon: Icons.shield_outlined,
                            value: insuranceProviderName?.trim().isNotEmpty == true
                                ? insuranceProviderName!.trim()
                                : 'None on file',
                          ),
                        ],
                      ),
                    ),
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

class _PerforatedEdge extends StatelessWidget {
  const _PerforatedEdge();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 1.5,
      width: double.infinity,
      child: CustomPaint(
        painter: _PerforatedEdgePainter(color: context.appColors.borderDefault.withValues(alpha: 0.4)),
      ),
    );
  }
}

class _PerforatedEdgePainter extends CustomPainter {
  const _PerforatedEdgePainter({required this.color});

  final Color color;

  static const _dashWidth = 6.0;
  static const _dashGap = 6.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5;

    var x = 0.0;
    while (x < size.width) {
      final end = (x + _dashWidth).clamp(0.0, size.width).toDouble();
      final y = size.height / 2;
      canvas.drawLine(Offset(x, y), Offset(end, y), paint);
      x += _dashWidth + _dashGap;
    }
  }

  @override
  bool shouldRepaint(covariant _PerforatedEdgePainter oldDelegate) => color != oldDelegate.color;
}
