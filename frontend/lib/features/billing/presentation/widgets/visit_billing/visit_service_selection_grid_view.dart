<<<<<<< HEAD
=======
import 'dart:async';

>>>>>>> master
import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/components/app_icon_button.dart';
import 'package:ai_clinic/core/ui/components/app_money_display.dart';
import 'package:ai_clinic/core/ui/motion/app_motion.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
import 'package:ai_clinic/features/service_catalog/domain/eligible_service.dart';
import 'package:ai_clinic/features/billing/domain/visit_billing_models.dart';

/// Grid catalog layout for service selection (web `ServiceSelectionGridView`).
class VisitServiceSelectionGridView extends StatelessWidget {
  const VisitServiceSelectionGridView({
    required this.services,
    required this.selectedIds,
    required this.selectedLines,
    required this.currency,
    required this.onToggle,
    required this.onQuantityChange,
    super.key,
  });

  final List<EligibleService> services;
  final Set<String> selectedIds;
  final List<VisitSelectedServiceLine> selectedLines;
  final String currency;
  final void Function(EligibleService service, bool selected) onToggle;
  final void Function(String serviceId, int quantity) onQuantityChange;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = switch (constraints.maxWidth) {
          >= 1024 => 4,
          >= 640 => 3,
          _ => 2,
        };

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.all(AppSpacing.space5),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: AppSpacing.space3,
            mainAxisSpacing: AppSpacing.space3,
            mainAxisExtent: 120,
          ),
          itemCount: services.length,
          itemBuilder: (context, index) {
            final service = services[index];
            final isSelected = selectedIds.contains(service.serviceId);
            final line = selectedLines
                .cast<VisitSelectedServiceLine?>()
                .firstWhere(
                  (entry) => entry?.serviceId == service.serviceId,
                  orElse: () => null,
                );
            final quantity = line?.quantity ?? 1;

            return _AnimatedGridTile(
              index: index,
              child: _ServiceGridCard(
                service: service,
                currency: currency,
                isSelected: isSelected,
                quantity: quantity,
                onToggle: () => onToggle(service, !isSelected),
                onDecrease: quantity > 1
                    ? () => onQuantityChange(service.serviceId, quantity - 1)
                    : null,
                onIncrease: quantity < 99
                    ? () => onQuantityChange(service.serviceId, quantity + 1)
                    : null,
              ),
            );
          },
        );
      },
    );
  }
}

class _AnimatedGridTile extends StatefulWidget {
  const _AnimatedGridTile({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<_AnimatedGridTile> createState() => _AnimatedGridTileState();
}

class _AnimatedGridTileState extends State<_AnimatedGridTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;
<<<<<<< HEAD
=======
  Timer? _startTimer;
>>>>>>> master

  static const _staggerStepMs = 20;
  static const _maxStaggerMs = 200;

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
      duration: reducedMotion ? Duration.zero : AppMotionDuration.quick,
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: AppMotion.outCurve,
    );

    final delay = reducedMotion
        ? Duration.zero
        : Duration(
            milliseconds: (widget.index * _staggerStepMs).clamp(
              0,
              _maxStaggerMs,
            ),
          );

    if (delay == Duration.zero) {
      _controller.forward();
    } else {
<<<<<<< HEAD
      Future<void>.delayed(delay, () {
=======
      _startTimer = Timer(delay, () {
>>>>>>> master
        if (mounted) {
          _controller.forward();
        }
      });
    }
  }

  @override
  void dispose() {
<<<<<<< HEAD
=======
    _startTimer?.cancel();
>>>>>>> master
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppMotion.animatedPreset(
      context: context,
      preset: AppMotionPreset.fadeScale,
      animation: _animation,
      child: widget.child,
    );
  }
}

class _ServiceGridCard extends StatelessWidget {
  const _ServiceGridCard({
    required this.service,
    required this.currency,
    required this.isSelected,
    required this.quantity,
    required this.onToggle,
    required this.onDecrease,
    required this.onIncrease,
  });

  final EligibleService service;
  final String currency;
  final bool isSelected;
  final int quantity;
  final VoidCallback onToggle;
  final VoidCallback? onDecrease;
  final VoidCallback? onIncrease;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return AnimatedContainer(
      duration: AppMotion.prefersReducedMotion(context)
          ? Duration.zero
          : AppMotionDuration.fast,
      curve: AppMotion.standardCurve,
      decoration: BoxDecoration(
        color: isSelected ? colors.surfaceSelected : colors.surfaceDefault,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: isSelected ? colors.actionPrimary : colors.borderDefault,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isSelected)
            ColoredBox(
              color: colors.actionPrimary,
              child: const SizedBox(height: 2),
            ),
          Expanded(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onToggle,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.space3 + 2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              service.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.bodyStrong(context).copyWith(
                                color: colors.textPrimary,
                                height: 1.3,
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.space2),
                          _SelectionIndicator(
                            isSelected: isSelected,
                            colors: colors,
                          ),
                        ],
                      ),
                      const Spacer(),
                      DefaultTextStyle(
                        style: AppTypography.bodySm(context).copyWith(
                          color: colors.textPrimary,
                          fontFamily: 'monospace',
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                        child: AppMoneyDisplay(
                          amount: service.unitPrice.asDouble,
                          currency: currency,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (isSelected)
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: colors.borderSubtle)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.space3,
                  vertical: AppSpacing.space2,
                ),
                child: Row(
                  children: [
                    Text(
                      'Qty',
                      style: AppTypography.caption(
                        context,
                      ).copyWith(color: colors.textTertiary),
                    ),
                    const Spacer(),
                    AppIconButton(
                      icon: const Icon(Icons.remove_rounded, size: 14),
                      label: 'Decrease quantity for ${service.name}',
                      size: AppIconButtonSize.sm,
                      onPressed: onDecrease,
                    ),
                    SizedBox(
                      width: 28,
                      child: Text(
                        '$quantity',
                        textAlign: TextAlign.center,
                        style: AppTypography.bodySm(context).copyWith(
                          fontFamily: 'monospace',
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    AppIconButton(
                      icon: const Icon(Icons.add_rounded, size: 14),
                      label: 'Increase quantity for ${service.name}',
                      size: AppIconButtonSize.sm,
                      onPressed: onIncrease,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SelectionIndicator extends StatelessWidget {
  const _SelectionIndicator({required this.isSelected, required this.colors});

  final bool isSelected;
  final AppSemanticColors colors;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: AppMotion.prefersReducedMotion(context)
          ? Duration.zero
          : AppMotionDuration.fast,
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isSelected ? colors.actionPrimary : colors.surfaceDefault,
        border: Border.all(
          color: isSelected ? colors.actionPrimary : colors.borderDefault,
        ),
      ),
      child: isSelected
          ? Icon(Icons.check_rounded, size: 12, color: colors.actionPrimaryFg)
          : null,
    );
  }
}
