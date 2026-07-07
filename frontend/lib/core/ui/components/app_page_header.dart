import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

/// Page-level header with optional breadcrumb, actions, and tabs slots (web `PageHeader`).
class AppPageHeader extends StatelessWidget {
  const AppPageHeader({
    required this.title,
    this.description,
    this.breadcrumb,
    this.actions,
    this.tabs,
    super.key,
  });

  final String title;
  final String? description;
  final Widget? breadcrumb;
  final Widget? actions;
  final Widget? tabs;

  static const _maxDescriptionWidth = 672.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Semantics(
      header: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: AppSpacing.space4,
        children: [
          ?breadcrumb,
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.start,
            spacing: AppSpacing.space4,
            runSpacing: AppSpacing.space4,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: AppSpacing.space1,
                  children: [
                    Text(
                      title,
                      style: AppTypography.h1(context).copyWith(color: colors.textPrimary),
                    ),
                    if (description != null)
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: _maxDescriptionWidth),
                        child: Text(
                          description!,
                          style: AppTypography.body(context).copyWith(color: colors.textSecondary),
                        ),
                      ),
                  ],
                ),
              ),
              if (actions != null)
                Wrap(
                  spacing: AppSpacing.space2,
                  runSpacing: AppSpacing.space2,
                  children: [actions!],
                ),
            ],
          ),
          ?tabs,
        ],
      ),
    );
  }
}
