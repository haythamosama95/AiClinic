import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/app_spacing.dart';

import 'foundation_constants.dart';

/// Aside + main layout matching web `DevSectionLayout`.
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

        if (!isLarge) {
          return child;
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 208,
              child: Align(
                alignment: Alignment.topCenter,
                child: SingleChildScrollView(
                  primary: false,
                  padding: const EdgeInsetsDirectional.only(end: AppSpacing.space2),
                  child: nav,
                ),
              ),
            ),
            SizedBox(width: gap),
            Expanded(child: child),
          ],
        );
      },
    );
  }
}

/// Sticky side navigation wrapper used inside [DevSectionLayout].
class DevSectionStickyNav extends StatelessWidget {
  const DevSectionStickyNav({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return child;
  }
}
