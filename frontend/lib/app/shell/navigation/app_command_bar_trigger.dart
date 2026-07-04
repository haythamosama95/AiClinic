import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

/// Command bar trigger placeholder (`04-components` C2 / C8).
class AppCommandBarTrigger extends StatelessWidget {
  const AppCommandBarTrigger({this.onPressed, super.key});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = MediaQuery.sizeOf(context).width;
        final preferred = screenWidth < 640 ? screenWidth * 0.42 : 448.0;
        final maxWidth = constraints.maxWidth.isFinite ? constraints.maxWidth : preferred;
        final triggerWidth = preferred.clamp(48.0, maxWidth.clamp(48.0, 448.0)).toDouble();

        return SizedBox(
          width: triggerWidth,
          child: Material(
            color: colors.surfaceSunken,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
              side: BorderSide(color: colors.borderDefault),
            ),
            child: InkWell(
              onTap: onPressed,
              borderRadius: BorderRadius.circular(AppRadius.md),
              hoverColor: colors.surfaceHover,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space3, vertical: 6),
                child: Row(
                  children: [
                    Icon(Icons.search, size: 16, color: colors.iconMuted),
                    if (triggerWidth >= 120) ...[
                      const SizedBox(width: AppSpacing.space2),
                      Expanded(
                        child: Text(
                          'Search or jump to…',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.bodySm(context).copyWith(color: colors.textPlaceholder),
                        ),
                      ),
                    ],
                    if (screenWidth >= 640 && triggerWidth >= 160)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: colors.surfaceDefault,
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                          border: Border.all(color: colors.borderSubtle),
                        ),
                        child: Text('⌘K', style: AppTypography.bodySm(context)),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
