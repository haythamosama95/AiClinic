import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/foundation.dart';
import 'package:ai_clinic/core/ui/state/state.dart';

/// Toggles standard ↔ AI accent mode via [aiModeProvider].
class AppAiModeToggle extends ConsumerWidget {
  const AppAiModeToggle({
    this.showLabel = true,
    super.key,
  });

  /// Whether to show the mode label beside the icon.
  final bool showLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final typography = context.typography;
    final aiMode = ref.watch(aiModeProvider);

    return AppPressable(
      onTap: () => ref.read(aiModeProvider.notifier).toggleAiMode(),
      semanticLabel: aiMode ? 'Switch to standard mode' : 'Switch to AI mode',
      focusRingVariant: aiMode ? AppFocusRingVariant.ai : AppFocusRingVariant.standard,
      borderRadius: AppRadii.mdAll,
      child: AnimatedContainer(
        duration: AppDurations.base,
        curve: AppEasings.standard,
        padding: EdgeInsetsDirectional.symmetric(
          horizontal: AppSpacing.s3,
          vertical: AppSpacing.s1 + AppSpacing.s0_5,
        ),
        decoration: BoxDecoration(
          color: aiMode ? colors.surfaceAi : colors.surfaceDefault,
          border: Border.all(color: aiMode ? colors.borderAi : colors.borderDefault),
          borderRadius: AppRadii.mdAll,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(
              icon: LucideIcons.sparkles,
              dimension: AppSpacing.s4,
              color: aiMode ? colors.textAi : colors.iconDefault,
            ),
            if (showLabel) ...[
              const SizedBox(width: AppSpacing.s2),
              Text(
                aiMode ? 'AI mode' : 'Standard',
                style: typography.bodyStrong.copyWith(
                  color: aiMode ? colors.textAi : colors.textPrimary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
