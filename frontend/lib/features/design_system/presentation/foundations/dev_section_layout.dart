import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/app_spacing.dart';

import 'foundation_constants.dart';

/// Aside + main layout matching web `DevSectionLayout`.
///
/// On large screens the nav column stays fixed while only [child] scrolls.
class DevSectionLayout extends StatelessWidget {
  const DevSectionLayout({required this.nav, required this.child, super.key});

  final Widget nav;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isLarge = constraints.maxWidth >= FoundationBreakpoints.lg;
        final gap = isLarge ? AppSpacing.space12 : AppSpacing.space8;

        final scrollableChild = SingleChildScrollView(primary: true, child: child);

        if (!isLarge) {
          return scrollableChild;
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 208,
              child: SingleChildScrollView(
                padding: const EdgeInsetsDirectional.only(end: AppSpacing.space2),
                child: nav,
              ),
            ),
            SizedBox(width: gap),
            Expanded(child: scrollableChild),
          ],
        );
      },
    );
  }
}
