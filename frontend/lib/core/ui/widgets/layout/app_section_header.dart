import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/foundation.dart';

/// Section-level header with optional overline, title, description, and actions.
class AppSectionHeader extends StatelessWidget {
  /// Creates a section header.
  ///
  /// [actions] commonly holds compact [AppButton] controls aligned to the
  /// logical end.
  const AppSectionHeader({
    required this.title,
    this.overline,
    this.description,
    this.actions,
    super.key,
  });

  final String title;
  final String? overline;
  final String? description;
  final Widget? actions;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    return Wrap(
      spacing: AppSpacing.s4,
      runSpacing: AppSpacing.s4,
      crossAxisAlignment: WrapCrossAlignment.start,
      alignment: WrapAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (overline != null)
              Text(
                overline!,
                style: typography.overline.copyWith(color: colors.textTertiary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            Text(
              title,
              style: typography.h3.copyWith(color: colors.textPrimary),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (description != null) ...[
              const SizedBox(height: AppSpacing.s1),
              Text(
                description!,
                style: typography.bodySm.copyWith(color: colors.textSecondary),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
        if (actions != null)
          Wrap(
            spacing: AppSpacing.s2,
            runSpacing: AppSpacing.s2,
            alignment: WrapAlignment.end,
            children: [actions!],
          ),
      ],
    );
  }
}
