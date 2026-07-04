import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/app_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/theme_context_extensions.dart';

enum AppDividerOrientation { horizontal, vertical }

/// Hairline separator with optional centered label.
class AppDivider extends StatelessWidget {
  const AppDivider({
    super.key,
    this.orientation = AppDividerOrientation.horizontal,
    this.label,
  });

  final AppDividerOrientation orientation;
  final Widget? label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    if (orientation == AppDividerOrientation.vertical) {
      return Semantics(
        container: true,
        label: 'Divider',
        child: Container(width: 1, color: colors.borderSubtle),
      );
    }

    if (label != null) {
      return Semantics(
        container: true,
        label: 'Divider',
        child: Row(
          children: [
            Expanded(child: _line(colors)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s3),
              child: DefaultTextStyle(
                style: context.typography.caption.copyWith(
                  color: colors.textTertiary,
                ),
                child: label!,
              ),
            ),
            Expanded(child: _line(colors)),
          ],
        ),
      );
    }

    return Semantics(container: true, label: 'Divider', child: _line(colors));
  }

  Widget _line(AppColors colors) {
    return Container(height: 1, color: colors.borderSubtle);
  }
}
