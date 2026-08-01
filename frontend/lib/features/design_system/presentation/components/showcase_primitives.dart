import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
import 'package:ai_clinic/features/design_system/presentation/foundations/dev_section_registry.dart';
import 'package:ai_clinic/features/design_system/presentation/foundations/foundation_constants.dart';
import 'package:ai_clinic/features/design_system/presentation/widgets/dev_text_styles.dart';

/// Component showcase section wrapper (web `ShowcaseSection`).
class ShowcaseSection extends StatelessWidget {
  const ShowcaseSection({
    required this.id,
    required this.title,
    required this.child,
    this.description,
    this.componentName,
    super.key,
  });

  final String id;
  final String title;
  final String? description;
  final String? componentName;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return KeyedSubtree(
      key: DevSectionRegistry.keyFor(id),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: colors.borderSubtle)),
            ),
            child: Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.space4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: AppSpacing.space3,
                    runSpacing: AppSpacing.space1,
                    children: [
                      Text(title, style: DevTextStyles.h3(context)),
                      if (componentName != null)
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: colors.surfaceSunken,
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space2, vertical: 2),
                            child: Text(
                              componentName!,
                              style: AppTypography.caption(context).copyWith(
                                fontFamily: AppTypography.mono(context).fontFamily,
                                color: colors.textTertiary,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (description != null) ...[
                    const SizedBox(height: AppSpacing.space1),
                    Text(
                      description!,
                      style: AppTypography.body(context).copyWith(color: colors.textSecondary),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.space6),
          child,
        ],
      ),
    );
  }
}

/// Responsive grid for showcase demos (web `ShowcaseDemoGrid`).
class ShowcaseDemoGrid extends StatelessWidget {
  const ShowcaseDemoGrid({
    required this.children,
    this.columns = 2,
    super.key,
  });

  final List<Widget> children;
  final int columns;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columnCount = constraints.maxWidth >= FoundationBreakpoints.sm ? columns : 1;
        final cellWidth = columnCount == 1
            ? constraints.maxWidth
            : (constraints.maxWidth - AppSpacing.space6 * (columnCount - 1)) / columnCount;

        return Wrap(
          spacing: AppSpacing.space6,
          runSpacing: AppSpacing.space6,
          children: children
              .map((child) => SizedBox(width: cellWidth, child: child))
              .toList(),
        );
      },
    );
  }
}

/// Single showcase demo card (web `ShowcaseDemo`).
class ShowcaseDemo extends StatelessWidget {
  const ShowcaseDemo({
    required this.label,
    required this.child,
    this.propsHint,
    super.key,
  });

  final String label;
  final String? propsHint;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceDefault,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: colors.borderDefault),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.space4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(label, style: AppTypography.bodyStrong(context))),
                if (propsHint != null)
                  Text(
                    propsHint!,
                    style: AppTypography.caption(context).copyWith(
                      fontFamily: AppTypography.mono(context).fontFamily,
                      color: colors.textTertiary,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.space3),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 40),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Variant matrix row (web `ShowcaseVariantMatrix`).
class ShowcaseVariantMatrix extends StatelessWidget {
  const ShowcaseVariantMatrix({
    required this.title,
    required this.children,
    super.key,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppTypography.overline(context).copyWith(color: context.appColors.textTertiary)),
        const SizedBox(height: AppSpacing.space3),
        Wrap(
          spacing: AppSpacing.space2,
          runSpacing: AppSpacing.space2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: children,
        ),
      ],
    );
  }
}

/// Placeholder for sections not yet implemented (web `PlaceholderSection`).
class PlaceholderSection extends StatelessWidget {
  const PlaceholderSection({
    required this.title,
    required this.message,
    super.key,
  });

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceSunken,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: colors.borderDefault, style: BorderStyle.solid),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.space8),
        child: Center(
          child: Column(
            children: [
              Text(title, style: AppTypography.bodyStrong(context)),
              const SizedBox(height: AppSpacing.space2),
              Text(
                message,
                style: AppTypography.body(context).copyWith(color: colors.textSecondary),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
