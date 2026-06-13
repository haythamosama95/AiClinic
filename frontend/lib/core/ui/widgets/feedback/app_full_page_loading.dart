import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/feedback/app_feedback.dart';

/// Full-area loading state: spinner centered in the available space.
class AppFullPageLoading extends StatelessWidget {
  const AppFullPageLoading({this.message, super.key});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final theme = Theme.of(context);

    return SizedBox.expand(
      child: ColoredBox(
        color: colors.background,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AppCircularProgress(),
              if (message != null) ...[
                const SizedBox(height: SpacingTokens.md),
                Text(
                  message!,
                  style: theme.textTheme.bodyMedium?.copyWith(color: colors.mutedForeground),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
