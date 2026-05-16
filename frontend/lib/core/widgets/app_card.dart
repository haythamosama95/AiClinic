import 'package:flutter/material.dart';

import 'package:ai_clinic/app/theme/app_colors.dart';

/// Card shell with consistent padding and optional title for feature screens.
class AppCard extends StatelessWidget {
  const AppCard({super.key, this.title, this.subtitle, required this.child, this.padding, this.actions});

  final String? title;
  final String? subtitle;
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final contentPadding = padding ?? const EdgeInsets.all(AppSpacing.lg);

    return Card(
      child: Padding(
        padding: contentPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (title != null || actions != null)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (title != null) Text(title!, style: textTheme.titleLarge),
                        if (subtitle != null) ...[
                          const SizedBox(height: AppSpacing.xs),
                          Text(subtitle!, style: textTheme.bodyMedium),
                        ],
                      ],
                    ),
                  ),
                  if (actions != null) ...actions!,
                ],
              ),
            if (title != null || actions != null) const SizedBox(height: AppSpacing.md),
            child,
          ],
        ),
      ),
    );
  }
}
