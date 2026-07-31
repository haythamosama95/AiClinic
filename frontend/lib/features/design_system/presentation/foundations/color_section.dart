import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/app_contrast.dart';
import 'package:ai_clinic/core/ui/theme/app_elevation.dart' show AppElevationContext;
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

import 'color_swatch.dart';
import 'foundation_constants.dart';
import 'foundation_section.dart';

/// Color foundation section with contrast cards and surface swatches.
class ColorSection extends StatelessWidget {
  const ColorSection({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return FoundationSection(
      id: 'colors',
      title: 'Color',
      description: 'Semantic pairs with WCAG 2.2 AA contrast verification in both themes.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = FoundationBreakpoints.gridColumns(
                constraints.maxWidth,
                smCols: 2,
                lgCols: 4,
              );
              return _ResponsiveGrid(
                columns: columns,
                gap: AppSpacing.space4,
                children: colorPairs.map((pair) {
                  final fg = isDark ? pair.darkFg : pair.fg;
                  final bg = isDark ? pair.darkBg : pair.bg;
                  final ratio = AppContrast.contrastRatio(fg, bg);
                  final pass = AppContrast.meetsAA(ratio);

                  return DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      border: Border.all(color: colors.borderDefault),
                      boxShadow: context.appElevation.shadowsFor(1),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            height: 80,
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space4),
                            color: bg,
                            child: Text(
                              pair.label,
                              style: AppTypography.bodyStrong(context).copyWith(color: fg),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          Container(
                            color: colors.surfaceDefault,
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.space3,
                              vertical: AppSpacing.space2,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  AppContrast.formatContrast(ratio),
                                  style: AppTypography.caption(context),
                                ),
                                Text(
                                  pass ? 'AA ✓' : 'Fail',
                                  style: AppTypography.caption(context).copyWith(
                                    fontWeight: FontWeight.w500,
                                    color: pass ? colors.statusSuccessFg : colors.statusDangerFg,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
          const SizedBox(height: AppSpacing.space8),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = FoundationBreakpoints.gridColumns(
                constraints.maxWidth,
                smCols: 2,
                lgCols: 4,
              );
              return _ResponsiveGrid(
                columns: columns,
                gap: AppSpacing.space4,
                children: [
                  FoundationColorSwatch(label: 'Canvas', color: colors.surfaceCanvas),
                  FoundationColorSwatch(label: 'Default', color: colors.surfaceDefault),
                  FoundationColorSwatch(
                    label: 'Raised',
                    color: colors.surfaceRaised,
                    boxShadow: context.appElevation.shadowsFor(1),
                  ),
                  FoundationColorSwatch(label: 'Sunken', color: colors.surfaceSunken),
                  FoundationColorSwatch(label: 'Muted', color: colors.surfaceMuted),
                  FoundationColorSwatch(label: 'Selected', color: colors.surfaceSelected),
                  FoundationColorSwatch(label: 'AI surface', color: colors.surfaceAi),
                  FoundationColorSwatch(label: 'Action primary', color: colors.actionPrimary),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ResponsiveGrid extends StatelessWidget {
  const _ResponsiveGrid({
    required this.columns,
    required this.gap,
    required this.children,
  });

  final int columns;
  final double gap;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (columns == 1) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) SizedBox(height: gap),
            children[i],
          ],
        ],
      );
    }

    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += columns) {
      final rowChildren = children.sublist(i, (i + columns).clamp(0, children.length));
      rows.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var j = 0; j < rowChildren.length; j++) ...[
              if (j > 0) SizedBox(width: gap),
              Expanded(child: rowChildren[j]),
            ],
            for (var j = rowChildren.length; j < columns; j++) ...[
              SizedBox(width: gap),
              const Expanded(child: SizedBox()),
            ],
          ],
        ),
      );
      if (i + columns < children.length) {
        rows.add(SizedBox(height: gap));
      }
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
  }
}
