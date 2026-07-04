import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/foundation.dart';

/// Section heading used across theme showcase tabs.
class ShowcaseSection extends StatelessWidget {
  const ShowcaseSection({
    required this.title,
    required this.child,
    this.description,
    this.id,
    super.key,
  });

  final String? id;
  final String title;
  final String? description;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    return Semantics(
      container: true,
      child: Column(
        key: id != null ? Key(id!) : null,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: colors.borderSubtle)),
            ),
            child: Padding(
              padding: const EdgeInsetsDirectional.only(bottom: AppSpacing.s4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: typography.h2.copyWith(color: colors.textPrimary),
                  ),
                  if (description != null) ...[
                    const SizedBox(height: AppSpacing.s1),
                    Text(
                      description!,
                      style: typography.body.copyWith(color: colors.textSecondary),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.s6),
          child,
        ],
      ),
    );
  }
}

/// Responsive wrap grid for component demos.
class ShowcaseDemoGrid extends StatelessWidget {
  const ShowcaseDemoGrid({
    required this.children,
    this.minItemWidth = 160,
    this.gap = AppSpacing.s3,
    super.key,
  });

  final List<Widget> children;
  final double minItemWidth;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = math.max(1, (constraints.maxWidth / minItemWidth).floor());
        final itemWidth = columns == 1
            ? constraints.maxWidth
            : (constraints.maxWidth - gap * (columns - 1)) / columns;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final child in children)
              SizedBox(width: itemWidth, child: child),
          ],
        );
      },
    );
  }
}

/// Color swatch with caption label.
class ShowcaseSwatch extends StatelessWidget {
  const ShowcaseSwatch({
    required this.label,
    required this.color,
    this.borderColor,
    this.shadows,
    super.key,
  });

  final String label;
  final Color color;
  final Color? borderColor;
  final List<BoxShadow>? shadows;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: AppSpacing.s12 + AppSpacing.s2,
          decoration: BoxDecoration(
            color: color,
            borderRadius: AppRadii.lgAll,
            border: Border.all(color: borderColor ?? colors.borderSubtle),
            boxShadow: shadows,
          ),
        ),
        const SizedBox(height: AppSpacing.s2),
        Text(
          label,
          style: typography.caption.copyWith(color: colors.textTertiary),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

/// Semantic color pair card with contrast readout.
class ShowcaseColorPairCard extends StatelessWidget {
  const ShowcaseColorPairCard({
    required this.label,
    required this.foreground,
    required this.background,
    super.key,
  });

  final String label;
  final Color foreground;
  final Color background;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final ratio = contrastRatio(foreground, background);
    final passesAa = ratio >= 4.5;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: AppRadii.lgAll,
        border: Border.all(color: colors.borderDefault),
        boxShadow: AppShadows.forLevel(1, Theme.of(context).brightness),
      ),
      child: ClipRRect(
        borderRadius: AppRadii.lgAll,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: AppSpacing.s16 + AppSpacing.s4,
              alignment: Alignment.center,
              padding: const EdgeInsetsDirectional.symmetric(horizontal: AppSpacing.s4),
              color: background,
              child: Text(
                label,
                style: typography.bodyStrong.copyWith(color: foreground),
                textAlign: TextAlign.center,
              ),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.symmetric(
                horizontal: AppSpacing.s3,
                vertical: AppSpacing.s2,
              ),
              child: Row(
                children: [
                  Text(
                    formatContrastRatio(ratio),
                    style: typography.caption.copyWith(color: colors.textTertiary),
                  ),
                  const Spacer(),
                  Text(
                    passesAa ? 'AA ✓' : 'Fail',
                    style: typography.caption.copyWith(
                      color: passesAa ? colors.statusSuccessFg : colors.statusDangerFg,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Spacing token bar visualization.
class ShowcaseSpacingBar extends StatelessWidget {
  const ShowcaseSpacingBar({required this.label, required this.size, super.key});

  final String label;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    return Row(
      children: [
        SizedBox(
          width: AppSpacing.s12,
          child: Text(
            label,
            style: typography.caption.copyWith(color: colors.textTertiary),
          ),
        ),
        Container(
          width: size,
          height: AppSpacing.s4,
          decoration: BoxDecoration(
            color: colors.actionPrimary,
            borderRadius: AppRadii.smAll,
          ),
        ),
        const SizedBox(width: AppSpacing.s2),
        Text(
          '${size.toInt()}px',
          style: typography.caption.copyWith(color: colors.textSecondary),
        ),
      ],
    );
  }
}

/// Typography specimen row.
class ShowcaseTypeSpecimen extends StatelessWidget {
  const ShowcaseTypeSpecimen({
    required this.token,
    required this.style,
    this.sample = 'The quick brown fox jumps over the lazy dog.',
    super.key,
  });

  final String token;
  final TextStyle style;
  final String sample;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: AppSpacing.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            token,
            style: typography.overline.copyWith(color: colors.textTertiary),
          ),
          const SizedBox(height: AppSpacing.s1),
          Text(
            sample,
            style: style.copyWith(color: colors.textPrimary),
          ),
        ],
      ),
    );
  }
}

/// Tabular figures demo using mono style.
class ShowcaseTabularFiguresDemo extends StatelessWidget {
  const ShowcaseTabularFiguresDemo({super.key});

  @override
  Widget build(BuildContext context) {
    final typography = context.typography;
    final colors = context.colors;
    const values = ['1,234.50', '98,765.00', '12,345.67'];

    return ShowcaseDemoGrid(
      minItemWidth: 120,
      children: [
        for (final value in values)
          Text(
            value,
            style: typography.mono.copyWith(
              color: colors.textPrimary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
      ],
    );
  }
}

double contrastRatio(Color foreground, Color background) {
  final l1 = _relativeLuminance(foreground);
  final l2 = _relativeLuminance(background);
  final lighter = math.max(l1, l2);
  final darker = math.min(l1, l2);
  return (lighter + 0.05) / (darker + 0.05);
}

String formatContrastRatio(double ratio) => '${ratio.toStringAsFixed(2)}:1';

double _relativeLuminance(Color color) {
  double channel(double value) {
    final c = value / 255;
    return c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  }

  final r = channel(color.r);
  final g = channel(color.g);
  final b = channel(color.b);
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}
