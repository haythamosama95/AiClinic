import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/components/app_checkbox.dart';
import 'package:ai_clinic/core/ui/components/app_icon_button.dart';
import 'package:ai_clinic/core/ui/components/app_money_display.dart';
import 'package:ai_clinic/core/ui/motion/app_motion.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
import 'package:ai_clinic/features/service_catalog/domain/eligible_service.dart';
import 'package:ai_clinic/features/billing/domain/visit_billing_models.dart';

/// List catalog layout for service selection (web `ServiceSelectionListView`).
class VisitServiceSelectionListView extends StatelessWidget {
  const VisitServiceSelectionListView({
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
    final colors = context.appColors;

    return ListView.separated(
      shrinkWrap: true,
      itemCount: services.length,
      separatorBuilder: (_, _) => Divider(height: 1, color: colors.borderSubtle),
      itemBuilder: (context, index) {
        final service = services[index];
        final isSelected = selectedIds.contains(service.serviceId);
        final line = selectedLines.cast<VisitSelectedServiceLine?>().firstWhere(
          (entry) => entry?.serviceId == service.serviceId,
          orElse: () => null,
        );
        final quantity = line?.quantity ?? 1;

        return _ServiceListRow(
          service: service,
          currency: currency,
          isSelected: isSelected,
          quantity: quantity,
          onToggle: () => onToggle(service, !isSelected),
          onCheckboxChanged: (checked) => onToggle(service, checked),
          onDecrease: quantity > 1 ? () => onQuantityChange(service.serviceId, quantity - 1) : null,
          onIncrease: quantity < 99 ? () => onQuantityChange(service.serviceId, quantity + 1) : null,
        );
      },
    );
  }
}

class _ServiceListRow extends StatelessWidget {
  const _ServiceListRow({
    required this.service,
    required this.currency,
    required this.isSelected,
    required this.quantity,
    required this.onToggle,
    required this.onCheckboxChanged,
    required this.onDecrease,
    required this.onIncrease,
  });

  final EligibleService service;
  final String currency;
  final bool isSelected;
  final int quantity;
  final VoidCallback onToggle;
  final ValueChanged<bool> onCheckboxChanged;
  final VoidCallback? onDecrease;
  final VoidCallback? onIncrease;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final reducedMotion = AppMotion.prefersReducedMotion(context);

    return AnimatedContainer(
      duration: reducedMotion ? Duration.zero : AppMotionDuration.fast,
      curve: AppMotion.standardCurve,
      color: isSelected ? colors.surfaceSelected.withValues(alpha: 0.6) : Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space5, vertical: AppSpacing.space3 + 2),
        child: Row(
          children: [
            Semantics(
              label: 'Select ${service.name}',
              child: AppCheckbox(
                value: isSelected ? AppCheckboxState.checked : AppCheckboxState.unchecked,
                onChanged: (checked) => onCheckboxChanged(checked == AppCheckboxState.checked),
              ),
            ),
            const SizedBox(width: AppSpacing.space3),
            Expanded(
              child: GestureDetector(
                onTap: onToggle,
                behavior: HitTestBehavior.opaque,
                child: Text(
                  service.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodyStrong(context).copyWith(color: colors.textPrimary, height: 1.3),
                ),
              ),
            ),
            AnimatedSize(
              duration: reducedMotion ? Duration.zero : AppMotionDuration.fast,
              curve: AppMotion.standardCurve,
              alignment: Alignment.centerRight,
              child: isSelected
                  ? Padding(
                      padding: const EdgeInsets.only(left: AppSpacing.space3),
                      child: _InlineQuantityStepper(
                        quantity: quantity,
                        serviceName: service.name,
                        onDecrease: onDecrease,
                        onIncrease: onIncrease,
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            const SizedBox(width: AppSpacing.space4),
            GestureDetector(
              onTap: onToggle,
              behavior: HitTestBehavior.opaque,
              child: DefaultTextStyle(
                style: AppTypography.bodySm(context).copyWith(
                  color: colors.textPrimary,
                  fontFamily: 'monospace',
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
                child: AppMoneyDisplay(amount: service.unitPrice, currency: currency),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InlineQuantityStepper extends StatelessWidget {
  const _InlineQuantityStepper({
    required this.quantity,
    required this.serviceName,
    required this.onDecrease,
    required this.onIncrease,
  });

  final int quantity;
  final String serviceName;
  final VoidCallback? onDecrease;
  final VoidCallback? onIncrease;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceDefault,
        borderRadius: BorderRadius.circular(AppSpacing.space2),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space1),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIconButton(
              icon: const Icon(Icons.remove_rounded, size: 14),
              label: 'Decrease quantity for $serviceName',
              size: AppIconButtonSize.sm,
              onPressed: onDecrease,
            ),
            SizedBox(
              width: 28,
              child: Text(
                '$quantity',
                textAlign: TextAlign.center,
                style: AppTypography.bodySm(
                  context,
                ).copyWith(fontFamily: 'monospace', fontFeatures: const [FontFeature.tabularFigures()]),
              ),
            ),
            AppIconButton(
              icon: const Icon(Icons.add_rounded, size: 14),
              label: 'Increase quantity for $serviceName',
              size: AppIconButtonSize.sm,
              onPressed: onIncrease,
            ),
          ],
        ),
      ),
    );
  }
}
