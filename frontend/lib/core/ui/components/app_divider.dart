import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

enum DividerOrientation { horizontal, vertical }

/// Hairline separator with optional centered label (web `Divider`).
class AppDivider extends StatelessWidget {
  const AppDivider({
    this.orientation = DividerOrientation.horizontal,
    this.label,
    super.key,
  });

  final DividerOrientation orientation;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    if (orientation == DividerOrientation.vertical) {
      return Semantics(
        container: true,
        label: 'Separator',
        child: ColoredBox(
          color: colors.borderSubtle,
          child: const SizedBox(width: 1),
        ),
      );
    }

    if (label != null) {
      return Semantics(
        container: true,
        label: label,
        child: Row(
          children: [
            Expanded(child: _DividerLine(color: colors.borderSubtle)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space3),
              child: Text(
                label!,
                style: AppTypography.caption(context).copyWith(color: colors.textTertiary),
              ),
            ),
            Expanded(child: _DividerLine(color: colors.borderSubtle)),
          ],
        ),
      );
    }

    return Semantics(
      container: true,
      label: 'Separator',
      child: _DividerLine(color: colors.borderSubtle),
    );
  }
}

class _DividerLine extends StatelessWidget {
  const _DividerLine({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 1,
      child: ColoredBox(color: color),
    );
  }
}
