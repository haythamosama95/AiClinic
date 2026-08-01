import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/components/app_button.dart';
import 'package:ai_clinic/core/ui/components/app_icon_button.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

/// Inline AI suggestion callout (web `AiSuggestion`).
class AppAiSuggestion extends StatelessWidget {
  const AppAiSuggestion({
    required this.message,
    this.onAccept,
    this.onDismiss,
    this.acceptLabel = 'Use suggestion',
    this.dismissLabel = 'Dismiss',
    this.dismissSuggestionLabel = 'Dismiss suggestion',
    super.key,
  });

  final String message;
  final VoidCallback? onAccept;
  final VoidCallback? onDismiss;
  final String acceptLabel;
  final String dismissLabel;
  final String dismissSuggestionLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Semantics(
      label: 'AI suggestion',
      container: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceAi,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: colors.borderAi),
        ),
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: AppSpacing.space4,
            vertical: AppSpacing.space3,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.only(top: 2),
                child: ExcludeSemantics(
                  child: Icon(
                    Icons.auto_awesome_outlined,
                    size: 16,
                    color: colors.textAi,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      message,
                      style: AppTypography.bodySm(context).copyWith(color: colors.textPrimary),
                    ),
                    if (onAccept != null || onDismiss != null) ...[
                      const SizedBox(height: AppSpacing.space2),
                      Wrap(
                        spacing: AppSpacing.space2,
                        runSpacing: AppSpacing.space2,
                        children: [
                          if (onAccept != null)
                            AppButton(
                              variant: AppButtonVariant.ai,
                              size: AppButtonSize.sm,
                              onPressed: onAccept,
                              child: Text(acceptLabel),
                            ),
                          if (onDismiss != null)
                            AppButton(
                              variant: AppButtonVariant.ghost,
                              size: AppButtonSize.sm,
                              onPressed: onDismiss,
                              child: Text(dismissLabel),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (onDismiss != null)
                AppIconButton(
                  icon: const Icon(Icons.close),
                  label: dismissSuggestionLabel,
                  variant: AppIconButtonVariant.ghost,
                  size: AppIconButtonSize.sm,
                  onPressed: onDismiss,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
