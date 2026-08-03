import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/app_elevation.dart' show AppElevationContext;
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

import 'foundation_constants.dart';
import 'foundation_section.dart';

/// Spacing, radius, and elevation foundation section.
class SpacingSection extends StatelessWidget {
  const SpacingSection({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return FoundationSection(
      id: 'spacing',
      title: 'Spacing, Radius & Elevation',
      description: '4px base unit. Elevation is border + soft shadow — kept cheap for low-end hardware.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Spacing', style: AppTypography.h3(context)),
          const SizedBox(height: AppSpacing.space4),
          Wrap(
            spacing: AppSpacing.space4,
            runSpacing: AppSpacing.space4,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              for (final token in spacingTokens)
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: AppSpacing.token(token),
                      height: 24,
                      decoration: BoxDecoration(
                        color: colors.actionPrimary,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.space2),
                    Text('space-$token', style: AppTypography.caption(context)),
                  ],
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.space10),
          Text('Radius', style: AppTypography.h3(context)),
          const SizedBox(height: AppSpacing.space4),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = FoundationBreakpoints.gridColumns(
                constraints.maxWidth,
                smCols: 3,
                lgCols: 6,
              );
              return _TokenGrid(
                columns: columns,
                gap: AppSpacing.space4,
                children: [
                  for (final token in radiusTokens)
                    Column(
                      children: [
                        Container(
                          height: 64,
                          decoration: BoxDecoration(
                            color: colors.surfaceMuted,
                            borderRadius: BorderRadius.circular(AppRadius.token(token)),
                            border: Border.all(color: colors.actionPrimary, width: 2),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.space2),
                        Text('radius-$token', style: AppTypography.caption(context)),
                      ],
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.space10),
          Text('Elevation', style: AppTypography.h3(context)),
          const SizedBox(height: AppSpacing.space4),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = FoundationBreakpoints.gridColumns(
                constraints.maxWidth,
                smCols: 2,
                lgCols: 4,
              );
              return _TokenGrid(
                columns: columns,
                gap: AppSpacing.space6,
                children: [
                  for (final token in elevationTokens)
                    Container(
                      height: 96,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: colors.surfaceDefault,
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                        border: Border.all(color: colors.borderSubtle),
                        boxShadow: context.appElevation.shadowsFor(int.parse(token)),
                      ),
                      child: Text(
                        'elevation-$token',
                        style: AppTypography.bodyStrong(context).copyWith(color: colors.textSecondary),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _TokenGrid extends StatelessWidget {
  const _TokenGrid({
    required this.columns,
    required this.gap,
    required this.children,
  });

  final int columns;
  final double gap;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += columns) {
      final slice = children.sublist(i, (i + columns).clamp(0, children.length));
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var j = 0; j < slice.length; j++) ...[
                if (j > 0) SizedBox(width: gap),
                Expanded(child: slice[j]),
              ],
              for (var j = slice.length; j < columns; j++) ...[
                SizedBox(width: gap),
                const Expanded(child: SizedBox()),
              ],
            ],
          ),
        ),
      );
      if (i + columns < children.length) {
        rows.add(SizedBox(height: gap));
      }
    }
    return Column(children: rows);
  }
}
