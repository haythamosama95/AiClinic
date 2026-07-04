import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/foundation.dart';
import 'package:ai_clinic/core/ui/widgets/actions/actions.dart';
import 'package:ai_clinic/core/ui/widgets/display/display.dart';

/// Zero-data scenario for [AppEmptyState].
enum AppEmptyStateVariant { firstRun, noResults, noAccess, error }

/// Centered invitation when a surface has no data, no matches, or no access.
class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    this.variant = AppEmptyStateVariant.firstRun,
    this.title,
    this.description,
    this.illustration,
    this.actionLabel,
    this.onAction,
    this.secondaryAction,
    this.shortcutKeys,
    super.key,
  });

  final AppEmptyStateVariant variant;
  final String? title;
  final String? description;
  final Widget? illustration;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Widget? secondaryAction;
  final List<String>? shortcutKeys;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final config = _configForVariant(variant);
    final resolvedTitle = title ?? config.title;
    final resolvedDescription = description ?? config.description;

    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: AppSpacing.s6,
        vertical: AppSpacing.s12,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          illustration ??
              Container(
                width: AppSpacing.s12,
                height: AppSpacing.s12,
                decoration: BoxDecoration(
                  color: colors.surfaceMuted,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: AppIcon(
                  icon: config.icon,
                  size: AppIconSize.lg,
                  color: colors.iconMuted,
                ),
              ),
          const SizedBox(height: AppSpacing.s4),
          Text(
            resolvedTitle,
            textAlign: TextAlign.center,
            style: typography.h3.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.s2),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 384),
            child: Text(
              resolvedDescription,
              textAlign: TextAlign.center,
              style: typography.body.copyWith(color: colors.textSecondary),
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: AppSpacing.s6),
            AppButton(
              label: actionLabel!,
              onPressed: onAction,
            ),
          ],
          if (secondaryAction != null) ...[
            const SizedBox(height: AppSpacing.s3),
            secondaryAction!,
          ],
          if (shortcutKeys != null && shortcutKeys!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.s4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Press',
                  style: typography.caption.copyWith(
                    color: colors.textTertiary,
                  ),
                ),
                const SizedBox(width: AppSpacing.s1),
                AppKbd(keys: shortcutKeys),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

({IconData icon, String title, String description}) _configForVariant(
  AppEmptyStateVariant variant,
) {
  return switch (variant) {
    AppEmptyStateVariant.firstRun => (
      icon: LucideIcons.folderOpen,
      title: 'Get started',
      description: 'Add your first record to begin.',
    ),
    AppEmptyStateVariant.noResults => (
      icon: LucideIcons.searchX,
      title: 'No matches',
      description: 'Try adjusting your filters or search terms.',
    ),
    AppEmptyStateVariant.noAccess => (
      icon: LucideIcons.lock,
      title: 'No access',
      description: 'You do not have permission to view this content.',
    ),
    AppEmptyStateVariant.error => (
      icon: LucideIcons.fileQuestion,
      title: 'Something went wrong',
      description: 'We could not load this content.',
    ),
  };
}
