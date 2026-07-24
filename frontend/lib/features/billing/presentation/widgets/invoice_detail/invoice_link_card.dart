import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/components/app_card.dart';
import 'package:ai_clinic/core/ui/components/app_icon_button.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

/// Flat navigation card for patient and visit shortcuts on the invoice detail page.
class InvoiceLinkCard extends StatelessWidget {
  const InvoiceLinkCard({
    required this.eyebrow,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onAction,
    this.badge,
    super.key,
  });

  final String eyebrow;
  final IconData icon;
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onAction;
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isRtl = Directionality.of(context) == TextDirection.rtl;

    return AppCard(
      variant: CardVariant.flat,
      padding: CardPadding.lg,
      child: Row(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surfaceSelected,
              borderRadius: BorderRadius.circular(AppRadius.xl),
            ),
            child: SizedBox(
              width: 40,
              height: 40,
              child: Icon(icon, size: 18, color: colors.textLink),
            ),
          ),
          const SizedBox(width: AppSpacing.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Wrap(
                  spacing: AppSpacing.space2,
                  runSpacing: AppSpacing.space1,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      eyebrow,
                      style: AppTypography.overline(
                        context,
                      ).copyWith(color: colors.textTertiary),
                    ),
                    ?badge,
                  ],
                ),
                const SizedBox(height: AppSpacing.space1),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodyStrong(
                    context,
                  ).copyWith(color: colors.textPrimary),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodySm(
                    context,
                  ).copyWith(color: colors.textSecondary),
                ),
              ],
            ),
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onAction,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              child: AppIconButton(
                variant: AppIconButtonVariant.secondary,
                size: AppIconButtonSize.lg,
                label: actionLabel,
                onPressed: onAction,
                icon: Transform.flip(
                  flipX: isRtl,
                  child: const Icon(Icons.arrow_forward, size: 18),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
