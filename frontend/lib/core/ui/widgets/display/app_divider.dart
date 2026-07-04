import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/foundation.dart';

/// Orientation for [AppDivider].
enum AppDividerOrientation {
  horizontal,
  vertical,
}

/// Hairline separator with optional centered label.
class AppDivider extends StatelessWidget {
  const AppDivider({
    this.orientation = AppDividerOrientation.horizontal,
    this.label,
    super.key,
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
        child: Container(
          width: AppSpacing.sPx,
          alignment: Alignment.center,
          color: colors.borderSubtle,
        ),
      );
    }

    if (label != null) {
      final typography = context.typography;
      return Semantics(
        container: true,
        label: 'Divider',
        child: Row(
          children: [
            Expanded(child: _Hairline(color: colors.borderSubtle)),
            Padding(
              padding: const EdgeInsetsDirectional.symmetric(
                horizontal: AppSpacing.s3,
              ),
              child: DefaultTextStyle(
                style: typography.caption.copyWith(
                  color: colors.textTertiary,
                ),
                child: label!,
              ),
            ),
            Expanded(child: _Hairline(color: colors.borderSubtle)),
          ],
        ),
      );
    }

    return Semantics(
      container: true,
      label: 'Divider',
      child: _Hairline(color: colors.borderSubtle),
    );
  }
}

class _Hairline extends StatelessWidget {
  const _Hairline({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AppSpacing.sPx,
      width: double.infinity,
      child: ColoredBox(color: color),
    );
  }
}
