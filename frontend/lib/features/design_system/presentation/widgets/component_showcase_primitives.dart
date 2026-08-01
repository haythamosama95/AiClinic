import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
import 'package:ai_clinic/features/design_system/presentation/foundations/dev_section_registry.dart';

/// Component showcase section wrapper matching web `ShowcaseSection`.
class ComponentShowcaseSection extends StatelessWidget {
  const ComponentShowcaseSection({
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
                      Text(title, style: AppTypography.h3(context)),
                      if (componentName != null)
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: colors.surfaceSunken,
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.space2,
                              vertical: AppSpacing.space05,
                            ),
                            child: Text(
                              componentName!,
                              style: AppTypography.caption(context).copyWith(
                                fontFamily: 'monospace',
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

/// Grid layout for component demos matching web `ShowcaseDemoGrid`.
class ComponentShowcaseDemoGrid extends StatelessWidget {
  const ComponentShowcaseDemoGrid({
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
        final isWide = constraints.maxWidth >= 640;
        final columnCount = isWide ? columns : 1;

        return Wrap(
          spacing: AppSpacing.space6,
          runSpacing: AppSpacing.space6,
          children: children
              .map(
                (child) => SizedBox(
                  width: columnCount == 1
                      ? constraints.maxWidth
                      : (constraints.maxWidth - AppSpacing.space6 * (columnCount - 1)) / columnCount,
                  child: child,
                ),
              )
              .toList(),
        );
      },
    );
  }
}

/// Single component demo card matching web `ShowcaseDemo`.
class ComponentShowcaseDemo extends StatelessWidget {
  const ComponentShowcaseDemo({
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
                Expanded(
                  child: Text(label, style: AppTypography.bodyStrong(context)),
                ),
                if (propsHint != null)
                  Text(
                    propsHint!,
                    style: AppTypography.caption(context).copyWith(
                      fontFamily: 'monospace',
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
                child: Wrap(
                  spacing: AppSpacing.space3,
                  runSpacing: AppSpacing.space3,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [child],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
