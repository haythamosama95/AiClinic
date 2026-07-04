import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/theme.dart';

/// Page title region with optional breadcrumb, actions, and tabs slots.
///
/// Mirrors web `PageHeader`.
class PageHeader extends StatelessWidget {
  const PageHeader({
    required this.title,
    super.key,
    this.description,
    this.breadcrumb,
    this.actions,
    this.tabs,
  });

  final String title;
  final String? description;
  final Widget? breadcrumb;
  final Widget? actions;
  final Widget? tabs;

  static const double _descriptionMaxWidth = 672;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: AppSpacing.s4,
      children: [
        ?breadcrumb,
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: AppSpacing.s1,
                children: [
                  Text(
                    title,
                    style: typography.h1.copyWith(color: colors.textPrimary),
                  ),
                  if (description != null)
                    ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: _descriptionMaxWidth,
                      ),
                      child: Text(
                        description!,
                        style: typography.body.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (actions != null) ...[
              const SizedBox(width: AppSpacing.s4),
              actions!,
            ],
          ],
        ),
        ?tabs,
      ],
    );
  }
}
