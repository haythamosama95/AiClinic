import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/components/app_money_display.dart';
import 'package:ai_clinic/core/ui/motion/app_motion.dart';
import 'package:ai_clinic/core/ui/theme/app_color_primitives.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/core/money/money.dart';
import 'package:ai_clinic/features/billing/domain/visit_billing_models.dart';

/// Sticky selected-services summary (web `ServiceSelectionSidebar`).
class VisitServiceSelectionSidebar extends StatefulWidget {
  const VisitServiceSelectionSidebar({
    required this.selectedLines,
    required this.subtotal,
    required this.currency,
    super.key,
  });

  final List<VisitSelectedServiceLine> selectedLines;
  final Money subtotal;
  final String currency;

  @override
  State<VisitServiceSelectionSidebar> createState() =>
      _VisitServiceSelectionSidebarState();
}

class _VisitServiceSelectionSidebarState
    extends State<VisitServiceSelectionSidebar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    final reducedMotion = WidgetsBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .disableAnimations;
    _controller = AnimationController(
      vsync: this,
      duration: reducedMotion ? Duration.zero : AppMotionDuration.base,
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: AppMotion.outCurve,
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final elevation = context.appElevation;
    final reducedMotion = AppMotion.prefersReducedMotion(context);

    final card = AppCard(
      variant: CardVariant.raised,
      padding: CardPadding.lg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColorPrimitives.violet50,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.space2 + 2),
                  child: Icon(
                    Icons.receipt_long_outlined,
                    size: 18,
                    color: AppColorPrimitives.violet600,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Selected',
                      style: AppTypography.overline(
                        context,
                      ).copyWith(color: colors.textTertiary),
                    ),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '${widget.selectedLines.length} ',
                            style: AppTypography.h3(context).copyWith(
                              color: colors.textPrimary,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                          TextSpan(
                            text: widget.selectedLines.length == 1
                                ? 'service'
                                : 'services',
                            style: AppTypography.body(
                              context,
                            ).copyWith(color: colors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.space5),
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: colors.borderSubtle)),
            ),
            child: Padding(
              padding: const EdgeInsets.only(top: AppSpacing.space5),
              child: widget.selectedLines.isEmpty
                  ? Text(
                      'No services selected yet. Pick from the catalog.',
                      style: AppTypography.bodySm(
                        context,
                      ).copyWith(color: colors.textTertiary),
                    )
                  : Column(
                      children: [
                        for (final line in widget.selectedLines) ...[
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text.rich(
                                  TextSpan(
                                    children: [
                                      TextSpan(
                                        text: line.name,
                                        style: AppTypography.bodySm(
                                          context,
                                        ).copyWith(color: colors.textPrimary),
                                      ),
                                      if (line.quantity > 1)
                                        TextSpan(
                                          text: ' × ${line.quantity}',
                                          style: AppTypography.bodySm(context)
                                              .copyWith(
                                                color: colors.textTertiary,
                                              ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.space2),
                              AppMoneyDisplay(
                                amount: line.lineTotal,
                                currency: widget.currency,
                              ),
                            ],
                          ),
                          if (line != widget.selectedLines.last)
                            const SizedBox(height: AppSpacing.space2 + 2),
                        ],
                      ],
                    ),
            ),
          ),
          const SizedBox(height: AppSpacing.space5),
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: colors.borderSubtle)),
            ),
            child: Padding(
              padding: const EdgeInsets.only(top: AppSpacing.space4),
              child: Row(
                children: [
                  Text(
                    'Subtotal',
                    style: AppTypography.bodySm(
                      context,
                    ).copyWith(color: colors.textSecondary),
                  ),
                  const Spacer(),
                  AppMoneyDisplay(
                    amount: widget.subtotal,
                    currency: widget.currency,
                    emphasis: true,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    Widget content = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.x2l),
        boxShadow: elevation.shadows1,
      ),
      child: card,
    );

    if (reducedMotion) {
      return content;
    }

    return AppMotion.animatedPreset(
      context: context,
      preset: AppMotionPreset.slideInline,
      animation: _animation,
      child: content,
    );
  }
}
