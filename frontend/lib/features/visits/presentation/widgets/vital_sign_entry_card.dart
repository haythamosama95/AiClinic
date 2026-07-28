import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/widgets/widgets.dart';

/// Compact card for a single recorded vital sign measurement.
class VitalSignEntryCard extends StatelessWidget {
  const VitalSignEntryCard({
    required this.label,
    required this.value,
    this.unit,
    this.onEdit,
    this.onRemove,
    this.canEdit = true,
    super.key,
  });

  final String label;
  final String value;
  final String? unit;
  final VoidCallback? onEdit;
  final VoidCallback? onRemove;
  final bool canEdit;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final trimmedUnit = unit?.trim();
    final hasUnit = trimmedUnit != null && trimmedUnit.isNotEmpty;

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: SizedBox(
        width: double.infinity,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfaceDefault,
            border: Border.all(color: colors.borderSubtle),
          ),
          child: Stack(
            children: [
              PositionedDirectional(
                start: 0,
                top: 0,
                bottom: 0,
                child: ColoredBox(color: colors.actionPrimary.withValues(alpha: 0.5), child: const SizedBox(width: 3)),
              ),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.space4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            label.toUpperCase(),
                            style: AppTypography.caption(
                              context,
                            ).copyWith(color: colors.textTertiary, fontWeight: FontWeight.w500, letterSpacing: 0.6),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (canEdit) ...[
                          AppIconButton(
                            icon: Icon(Icons.edit_outlined, size: 15, color: colors.iconMuted),
                            label: 'Edit $label',
                            size: AppIconButtonSize.sm,
                            tooltipDisabled: true,
                            onPressed: onEdit,
                          ),
                          AppIconButton(
                            icon: Icon(Icons.delete_outline, size: 15, color: colors.iconMuted),
                            label: 'Remove $label',
                            size: AppIconButtonSize.sm,
                            tooltipDisabled: true,
                            onPressed: onRemove,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: AppSpacing.space2),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: value,
                            style: AppTypography.h2(context).copyWith(
                              color: colors.textPrimary,
                              height: 1,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                          if (hasUnit)
                            TextSpan(
                              text: ' $trimmedUnit',
                              style: AppTypography.bodySm(context).copyWith(color: colors.textSecondary),
                            ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
