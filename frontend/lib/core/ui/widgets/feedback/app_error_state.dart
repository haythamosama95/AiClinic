import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/foundation.dart';
import 'package:ai_clinic/core/ui/widgets/actions/actions.dart';

/// Failed-load treatment distinct from empty states; never shows raw stack traces.
class AppErrorState extends StatefulWidget {
  const AppErrorState({
    required this.message,
    this.title = 'Failed to load',
    this.onRetry,
    this.retryLabel = 'Try again',
    this.details,
    super.key,
  });

  final String title;
  final String message;
  final VoidCallback? onRetry;
  final String retryLabel;

  /// Optional sanitized technical detail (never a stack trace).
  final String? details;

  @override
  State<AppErrorState> createState() => _AppErrorStateState();
}

class _AppErrorStateState extends State<AppErrorState> {
  bool _detailsExpanded = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    return Semantics(
      container: true,
      liveRegion: true,
      label: widget.title,
      hint: widget.message,
      child: Padding(
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: AppSpacing.s6,
          vertical: AppSpacing.s12,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: AppSpacing.s12,
              height: AppSpacing.s12,
              decoration: BoxDecoration(
                color: colors.statusDangerSurface,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: AppIcon(
                icon: LucideIcons.triangleAlert,
                size: AppIconSize.lg,
                color: colors.statusDangerFg,
              ),
            ),
            const SizedBox(height: AppSpacing.s4),
            Text(
              widget.title,
              textAlign: TextAlign.center,
              style: typography.h3.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(height: AppSpacing.s2),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 384),
              child: Text(
                widget.message,
                textAlign: TextAlign.center,
                style: typography.body.copyWith(color: colors.textSecondary),
              ),
            ),
            if (widget.details != null) ...[
              const SizedBox(height: AppSpacing.s3),
              AppButton(
                label: _detailsExpanded ? 'Hide details' : 'Show details',
                variant: AppButtonVariant.link,
                size: AppButtonSize.sm,
                onPressed: () {
                  setState(() => _detailsExpanded = !_detailsExpanded);
                },
              ),
              AppCollapse(
                expanded: _detailsExpanded,
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(top: AppSpacing.s2),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 384),
                    child: Text(
                      widget.details!,
                      textAlign: TextAlign.center,
                      style: typography.bodySm.copyWith(
                        color: colors.textTertiary,
                      ),
                    ),
                  ),
                ),
              ),
            ],
            if (widget.onRetry != null) ...[
              const SizedBox(height: AppSpacing.s6),
              AppButton(
                label: widget.retryLabel,
                variant: AppButtonVariant.secondary,
                leadingIcon: LucideIcons.refreshCw,
                onPressed: widget.onRetry,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
