import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/foundation.dart';
import 'package:ai_clinic/core/ui/patterns/pattern_scaffold.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/dev/presentation/widgets/showcase_section.dart';

/// Foundations tab — colors, typography, spacing, motion, and The Signal.
class FoundationsShowcaseSection extends StatefulWidget {
  const FoundationsShowcaseSection({super.key});

  @override
  State<FoundationsShowcaseSection> createState() => _FoundationsShowcaseSectionState();
}

class _FoundationsShowcaseSectionState extends State<FoundationsShowcaseSection> {
  var _motionVisible = true;
  var _motionKey = 0;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final brightness = Theme.of(context).brightness;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Milestone 1',
          style: typography.overline.copyWith(color: colors.textTertiary),
        ),
        const SizedBox(height: AppSpacing.s1),
        Text(
          'Foundations',
          style: typography.h2.copyWith(color: colors.textPrimary),
        ),
        const SizedBox(height: AppSpacing.s2),
        Text(
          'Tokens, typography, spacing, motion, and The Signal.',
          style: typography.bodyLg.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: PatternScaffold.sectionGap),
        ShowcaseSection(
          id: 'colors',
          title: 'Color',
          description: 'Semantic pairs with WCAG 2.2 AA contrast verification in both themes.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ShowcaseDemoGrid(
                minItemWidth: 200,
                children: [
                  ShowcaseColorPairCard(
                    label: 'Primary text',
                    foreground: colors.textPrimary,
                    background: colors.surfaceCanvas,
                  ),
                  ShowcaseColorPairCard(
                    label: 'Secondary text',
                    foreground: colors.textSecondary,
                    background: colors.surfaceCanvas,
                  ),
                  ShowcaseColorPairCard(
                    label: 'Action primary',
                    foreground: colors.actionPrimaryFg,
                    background: colors.actionPrimary,
                  ),
                  ShowcaseColorPairCard(
                    label: 'AI action',
                    foreground: colors.actionAiFg,
                    background: colors.actionAi,
                  ),
                  ShowcaseColorPairCard(
                    label: 'Success',
                    foreground: colors.statusSuccessFg,
                    background: colors.statusSuccessSurface,
                  ),
                  ShowcaseColorPairCard(
                    label: 'Warning',
                    foreground: colors.statusWarningFg,
                    background: colors.statusWarningSurface,
                  ),
                  ShowcaseColorPairCard(
                    label: 'Danger',
                    foreground: colors.statusDangerFg,
                    background: colors.statusDangerSurface,
                  ),
                  ShowcaseColorPairCard(
                    label: 'Info',
                    foreground: colors.statusInfoFg,
                    background: colors.statusInfoSurface,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.s8),
              ShowcaseDemoGrid(
                children: [
                  ShowcaseSwatch(label: 'Canvas', color: colors.surfaceCanvas),
                  ShowcaseSwatch(label: 'Default', color: colors.surfaceDefault),
                  ShowcaseSwatch(
                    label: 'Raised',
                    color: colors.surfaceRaised,
                    shadows: AppShadows.forLevel(1, brightness),
                  ),
                  ShowcaseSwatch(label: 'Sunken', color: colors.surfaceSunken),
                  ShowcaseSwatch(label: 'Muted', color: colors.surfaceMuted),
                  ShowcaseSwatch(label: 'Selected', color: colors.surfaceSelected),
                  ShowcaseSwatch(label: 'AI surface', color: colors.surfaceAi),
                  ShowcaseSwatch(label: 'Action primary', color: colors.actionPrimary),
                ],
              ),
              const SizedBox(height: AppSpacing.s8),
              Text(
                'Primitive palettes',
                style: typography.title.copyWith(color: colors.textPrimary),
              ),
              const SizedBox(height: AppSpacing.s4),
              _PrimitivePaletteRow(
                label: 'Teal (deterministic)',
                colors: const [
                  AppColorPrimitives.teal50,
                  AppColorPrimitives.teal300,
                  AppColorPrimitives.teal500,
                  AppColorPrimitives.teal600,
                  AppColorPrimitives.teal800,
                ],
              ),
              const SizedBox(height: AppSpacing.s3),
              _PrimitivePaletteRow(
                label: 'Violet (AI)',
                colors: const [
                  AppColorPrimitives.violet50,
                  AppColorPrimitives.violet300,
                  AppColorPrimitives.violet500,
                  AppColorPrimitives.violet600,
                  AppColorPrimitives.violet800,
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: PatternScaffold.sectionGap),
        ShowcaseSection(
          id: 'typography',
          title: 'Typography',
          description: 'Full type scale with Arabic specimen and tabular figures.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ShowcaseTypeSpecimen(token: 'Display LG', style: typography.displayLg),
              ShowcaseTypeSpecimen(token: 'Display', style: typography.display),
              ShowcaseTypeSpecimen(token: 'H1', style: typography.h1),
              ShowcaseTypeSpecimen(token: 'H2', style: typography.h2),
              ShowcaseTypeSpecimen(token: 'H3', style: typography.h3),
              ShowcaseTypeSpecimen(token: 'Title', style: typography.title),
              ShowcaseTypeSpecimen(token: 'Body LG', style: typography.bodyLg),
              ShowcaseTypeSpecimen(token: 'Body', style: typography.body),
              ShowcaseTypeSpecimen(token: 'Body Strong', style: typography.bodyStrong),
              ShowcaseTypeSpecimen(token: 'Body SM', style: typography.bodySm),
              ShowcaseTypeSpecimen(token: 'Caption', style: typography.caption),
              ShowcaseTypeSpecimen(token: 'Overline', style: typography.overline),
              ShowcaseTypeSpecimen(token: 'Mono', style: typography.mono, sample: 'INV-2026-0042 · 09:30'),
              const SizedBox(height: AppSpacing.s4),
              Text(
                'Tabular figures',
                style: typography.title.copyWith(color: colors.textPrimary),
              ),
              const SizedBox(height: AppSpacing.s2),
              const ShowcaseTabularFiguresDemo(),
              const SizedBox(height: AppSpacing.s6),
              Text(
                'Arabic specimen',
                style: typography.title.copyWith(color: colors.textPrimary),
              ),
              const SizedBox(height: AppSpacing.s2),
              Text(
                'نظام عيادة ذكي يجمع بين الدقة السريرية والوضوح التشغيلي.',
                style: AppTypography.fromColors(
                  colors,
                  brightness: brightness,
                  arabic: true,
                ).bodyLg.copyWith(color: colors.textPrimary),
                textDirection: TextDirection.rtl,
              ),
            ],
          ),
        ),
        const SizedBox(height: PatternScaffold.sectionGap),
        ShowcaseSection(
          id: 'spacing',
          title: 'Spacing & elevation',
          description: 'Spacing scale, radius tokens, and elevation levels.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const ShowcaseSpacingBar(label: 's1', size: AppSpacing.s1),
              const ShowcaseSpacingBar(label: 's2', size: AppSpacing.s2),
              const ShowcaseSpacingBar(label: 's3', size: AppSpacing.s3),
              const ShowcaseSpacingBar(label: 's4', size: AppSpacing.s4),
              const ShowcaseSpacingBar(label: 's6', size: AppSpacing.s6),
              const ShowcaseSpacingBar(label: 's8', size: AppSpacing.s8),
              const ShowcaseSpacingBar(label: 's12', size: AppSpacing.s12),
              const SizedBox(height: AppSpacing.s6),
              ShowcaseDemoGrid(
                minItemWidth: 100,
                children: [
                  for (final entry in <(String, BorderRadius)>[
                    ('sm', AppRadii.smAll),
                    ('md', AppRadii.mdAll),
                    ('lg', AppRadii.lgAll),
                    ('xl', AppRadii.xlAll),
                    ('2xl', AppRadii.xxlAll),
                    ('full', AppRadii.fullAll),
                  ])
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          height: AppSpacing.s12,
                          decoration: BoxDecoration(
                            color: colors.surfaceMuted,
                            borderRadius: entry.$2,
                            border: Border.all(color: colors.borderDefault),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.s2),
                        Text(
                          'radius ${entry.$1}',
                          style: typography.caption.copyWith(color: colors.textTertiary),
                        ),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.s6),
              ShowcaseDemoGrid(
                children: [
                  for (final level in [0, 1, 2, 3])
                    ShowcaseSwatch(
                      label: 'elevation $level',
                      color: colors.surfaceRaised,
                      shadows: AppShadows.forLevel(level, brightness),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: PatternScaffold.sectionGap),
        ShowcaseSection(
          id: 'motion',
          title: 'Motion',
          description: 'Named presets with replay triggers and reduced-motion path.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: AppSpacing.s2,
                runSpacing: AppSpacing.s2,
                children: [
                  AppButton(
                    label: _motionVisible ? 'Replay motion' : 'Show motion',
                    variant: AppButtonVariant.secondary,
                    size: AppButtonSize.sm,
                    onPressed: () => setState(() {
                      if (_motionVisible) {
                        _motionKey++;
                      } else {
                        _motionVisible = true;
                      }
                    }),
                  ),
                  AppButton(
                    label: 'Hide',
                    variant: AppButtonVariant.ghost,
                    size: AppButtonSize.sm,
                    onPressed: () => setState(() => _motionVisible = false),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.s4),
              if (_motionVisible)
                ShowcaseDemoGrid(
                  minItemWidth: 140,
                  children: [
                    _MotionDemoTile(
                      key: ValueKey('fade-$_motionKey'),
                      label: 'fade',
                      child: AppFade(child: _motionBlock(colors)),
                    ),
                    _MotionDemoTile(
                      key: ValueKey('fade-scale-$_motionKey'),
                      label: 'fade-scale',
                      child: AppFadeScale(child: _motionBlock(colors)),
                    ),
                    _MotionDemoTile(
                      key: ValueKey('slide-up-$_motionKey'),
                      label: 'slide-up',
                      child: AppSlideUp(child: _motionBlock(colors)),
                    ),
                    _MotionDemoTile(
                      key: ValueKey('slide-inline-$_motionKey'),
                      label: 'slide-inline',
                      child: AppSlideInline(child: _motionBlock(colors)),
                    ),
                  ],
                ),
              const SizedBox(height: AppSpacing.s6),
              Wrap(
                spacing: AppSpacing.s4,
                runSpacing: AppSpacing.s2,
                children: [
                  for (final preset in AppMotionPreset.values)
                    Text(
                      preset.name,
                      style: typography.caption.copyWith(color: colors.textSecondary),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: PatternScaffold.sectionGap),
        ShowcaseSection(
          id: 'signal',
          title: 'The Signal',
          description: 'Teal deterministic accent and violet AI pulse placements.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ShowcaseDemoGrid(
                minItemWidth: 200,
                children: [
                  _SignalPlacementCard(
                    title: 'Nav indicator',
                    child: SizedBox(
                      height: AppSpacing.s12,
                      child: Stack(
                        children: [
                          PositionedDirectional(
                            start: 0,
                            top: AppSpacing.s2,
                            bottom: AppSpacing.s2,
                            child: AppSignalLine(
                              orientation: AppSignalOrientation.vertical,
                              length: AppSpacing.s8,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsetsDirectional.only(start: AppSpacing.s4),
                            child: Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: Text(
                                'Patients',
                                style: typography.bodyStrong.copyWith(color: colors.textPrimary),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  _SignalPlacementCard(
                    title: 'AI thinking',
                    child: SizedBox(
                      height: AppSpacing.s12,
                      child: Center(
                        child: AppSignalLine(
                          orientation: AppSignalOrientation.horizontal,
                          ai: true,
                          thinking: true,
                          length: AppSpacing.s16,
                        ),
                      ),
                    ),
                  ),
                  _SignalPlacementCard(
                    title: 'AI accent',
                    child: SizedBox(
                      height: AppSpacing.s12,
                      child: Center(
                        child: AppSignalLine(
                          orientation: AppSignalOrientation.horizontal,
                          ai: true,
                          glow: true,
                          length: AppSpacing.s16,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _motionBlock(AppColors colors) {
    return Container(
      height: AppSpacing.s10,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.surfaceSelected,
        borderRadius: AppRadii.mdAll,
      ),
      child: Text(
        'Motion',
        style: context.typography.caption.copyWith(color: colors.textPrimary),
      ),
    );
  }
}

class _PrimitivePaletteRow extends StatelessWidget {
  const _PrimitivePaletteRow({required this.label, required this.colors});

  final String label;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    final typography = context.typography;
    final border = context.colors.borderSubtle;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: typography.bodySm.copyWith(color: context.colors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.s2),
        Row(
          children: [
            for (final color in colors)
              Expanded(
                child: Container(
                  height: AppSpacing.s8,
                  margin: const EdgeInsetsDirectional.only(end: AppSpacing.s1),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: AppRadii.smAll,
                    border: Border.all(color: border),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _MotionDemoTile extends StatelessWidget {
  const _MotionDemoTile({required this.label, required this.child, super.key});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: context.typography.caption.copyWith(color: context.colors.textTertiary),
        ),
        const SizedBox(height: AppSpacing.s2),
        child,
      ],
    );
  }
}

class _SignalPlacementCard extends StatelessWidget {
  const _SignalPlacementCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: AppRadii.lgAll,
        border: Border.all(color: colors.borderDefault),
        color: colors.surfaceDefault,
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.all(AppSpacing.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: context.typography.bodyStrong.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(height: AppSpacing.s3),
            child,
          ],
        ),
      ),
    );
  }
}
