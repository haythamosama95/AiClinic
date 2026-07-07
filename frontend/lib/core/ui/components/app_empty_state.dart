import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/components/app_button.dart';
import 'package:ai_clinic/core/ui/components/app_kbd.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

/// Visual variant for [AppEmptyState] (web `EmptyStateVariant`).
enum AppEmptyStateVariant {
  firstRun,
  noResults,
  noAccess,
  error,
}

/// @deprecated Use [AppEmptyStateVariant].
typedef EmptyStateVariant = AppEmptyStateVariant;

/// Primary call-to-action for [AppEmptyState].
class EmptyStateAction {
  const EmptyStateAction({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;
}

/// Centered empty / no-data placeholder (web `EmptyState`).
class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    this.variant = AppEmptyStateVariant.firstRun,
    this.title,
    this.description,
    this.action,
    this.secondaryAction,
    this.shortcutHint,
    super.key,
  });

  final AppEmptyStateVariant variant;
  final String? title;
  final String? description;
  final EmptyStateAction? action;
  final Widget? secondaryAction;
  final List<String>? shortcutHint;

  static const _maxDescriptionWidth = 384.0;

  static const _defaults = <AppEmptyStateVariant, ({String title, String description, IconData icon})>{
    AppEmptyStateVariant.firstRun: (
      title: 'Get started',
      description: 'Add your first record to begin.',
      icon: Icons.folder_open,
    ),
    AppEmptyStateVariant.noResults: (
      title: 'No matches',
      description: 'Try adjusting your filters or search terms.',
      icon: Icons.search_off,
    ),
    AppEmptyStateVariant.noAccess: (
      title: 'No access',
      description: 'You do not have permission to view this content.',
      icon: Icons.lock_outline,
    ),
    AppEmptyStateVariant.error: (
      title: 'Something went wrong',
      description: 'We could not load this content.',
      icon: Icons.help_outline,
    ),
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final config = _defaults[variant]!;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.space6,
        vertical: AppSpacing.space12,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surfaceMuted,
              shape: BoxShape.circle,
            ),
            child: SizedBox(
              width: AppSpacing.space12,
              height: AppSpacing.space12,
              child: Icon(
                config.icon,
                size: 24,
                color: colors.iconMuted,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.space4),
          Text(
            title ?? config.title,
            style: AppTypography.h3(context).copyWith(color: colors.textPrimary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.space2),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _maxDescriptionWidth),
            child: Text(
              description ?? config.description,
              style: AppTypography.body(context).copyWith(color: colors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ),
          if (action != null) ...[
            const SizedBox(height: AppSpacing.space6),
            AppButton(
              variant: AppButtonVariant.primary,
              onPressed: action!.onPressed,
              child: Text(action!.label),
            ),
          ],
          if (secondaryAction != null) ...[
            const SizedBox(height: AppSpacing.space3),
            secondaryAction!,
          ],
          if (shortcutHint != null) ...[
            const SizedBox(height: AppSpacing.space4),
            Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Press ',
                  style: AppTypography.caption(context).copyWith(color: colors.textTertiary),
                ),
                AppKbd(keys: shortcutHint),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
