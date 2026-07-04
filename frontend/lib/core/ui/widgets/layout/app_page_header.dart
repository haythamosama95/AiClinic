import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/foundation.dart';

/// Page-level header with title, optional description, breadcrumb, actions, and tabs.
class AppPageHeader extends StatelessWidget {
  /// Creates a page header.
  ///
  /// [breadcrumb] and [tabs] are typically [AppBreadcrumb] and [AppTabs] from
  /// the navigation group. [actions] commonly holds [AppButton] controls.
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

  static double get _descriptionMaxWidth => AppBreakpoints.sm + AppSpacing.s8;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    return Semantics(
      header: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (breadcrumb != null) ...[
            breadcrumb!,
            const SizedBox(height: AppSpacing.s4),
          ],
          Wrap(
            spacing: AppSpacing.s4,
            runSpacing: AppSpacing.s4,
            crossAxisAlignment: WrapCrossAlignment.start,
            alignment: WrapAlignment.spaceBetween,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: typography.h1.copyWith(color: colors.textPrimary),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (description != null) ...[
                      const SizedBox(height: AppSpacing.s1),
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: _descriptionMaxWidth,
                        ),
                        child: Text(
                          description!,
                          style: typography.body.copyWith(
                            color: colors.textSecondary,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (actions != null)
                Wrap(
                  spacing: AppSpacing.s2,
                  runSpacing: AppSpacing.s2,
                  alignment: WrapAlignment.end,
                  children: [actions!],
                ),
            ],
          ),
          if (tabs != null) ...[
            const SizedBox(height: AppSpacing.s4),
            tabs!,
          ],
        ],
      ),
    );
  }
}
