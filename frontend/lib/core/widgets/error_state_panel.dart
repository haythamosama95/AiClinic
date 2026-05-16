import 'package:flutter/material.dart';

import 'package:ai_clinic/app/theme/app_colors.dart';
import 'package:ai_clinic/core/errors/failures.dart';

/// Full-width recoverable error surface for blocking or inline error states.
class ErrorStatePanel extends StatelessWidget {
  const ErrorStatePanel({
    super.key,
    required this.failure,
    this.onRetry,
    this.retryLabel = 'Try again',
    this.compact = false,
  });

  final AppFailure failure;
  final VoidCallback? onRetry;
  final String retryLabel;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final padding = compact ? AppSpacing.md : AppSpacing.lg;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(AppSpacing.borderRadius),
      ),
      padding: EdgeInsets.all(padding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline, color: colorScheme.onErrorContainer),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      failure.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(color: colorScheme.onErrorContainer),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      failure.message,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colorScheme.onErrorContainer),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (failure.recoverable && onRetry != null) ...[
            const SizedBox(height: AppSpacing.md),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                onPressed: onRetry,
                style: OutlinedButton.styleFrom(
                  foregroundColor: colorScheme.onErrorContainer,
                  side: BorderSide(color: colorScheme.onErrorContainer.withValues(alpha: 0.5)),
                ),
                child: Text(retryLabel),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
