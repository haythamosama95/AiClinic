import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/billing/domain/discount_scope.dart';

/// Explains mutual-exclusion between line and invoice discounts (V1-6 US3).
class DiscountScopeGuard extends StatelessWidget {
  const DiscountScopeGuard({
    required this.activeScope,
    required this.blockedScope,
    required this.onClearActiveScope,
    super.key,
  });

  final DiscountScope? activeScope;
  final DiscountScope blockedScope;
  final VoidCallback? onClearActiveScope;

  @override
  Widget build(BuildContext context) {
    if (activeScope == null || activeScope == blockedScope) {
      return const SizedBox.shrink();
    }

    final colors = context.semanticColors;
    final theme = Theme.of(context);
    final activeLabel = activeScope!.label;
    final blockedLabel = blockedScope.label;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.accent.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(SpacingTokens.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, size: 18, color: colors.accentForeground),
            const SizedBox(width: SpacingTokens.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '$blockedLabel discounts are disabled',
                    style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: SpacingTokens.xs),
                  Text(
                    'This invoice already has $activeLabel discounts. Clear them before applying $blockedLabel discounts.',
                    style: theme.textTheme.bodySmall?.copyWith(color: colors.mutedForeground),
                  ),
                  if (onClearActiveScope != null) ...[
                    const SizedBox(height: SpacingTokens.sm),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: AppButton(
                        label: 'Clear $activeLabel discounts',
                        variant: AppButtonVariant.outline,
                        expand: false,
                        onPressed: onClearActiveScope,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
