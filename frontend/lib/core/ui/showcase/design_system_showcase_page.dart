import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/providers/theme_provider.dart';
import 'package:ai_clinic/core/ui/motion/app_motion.dart';
import 'package:ai_clinic/core/ui/providers/density_provider.dart';
import 'package:ai_clinic/core/ui/providers/locale_provider.dart';
import 'package:ai_clinic/core/ui/providers/reduced_motion_provider.dart';
import 'package:ai_clinic/core/ui/showcase/components_showcase.dart';
import 'package:ai_clinic/core/ui/showcase/app_contrast.dart';
import 'package:ai_clinic/core/ui/theme/theme.dart';
import 'package:ai_clinic/core/ui/widgets/signal.dart';

/// Flutter reproduction of the web Foundations showcase page.
class DesignSystemShowcasePage extends ConsumerStatefulWidget {
  const DesignSystemShowcasePage({super.key});

  @override
  ConsumerState<DesignSystemShowcasePage> createState() => _DesignSystemShowcasePageState();
}

enum _ShowcaseTab { foundations, components }

class _DesignSystemShowcasePageState extends ConsumerState<DesignSystemShowcasePage> {
  AppMotionPreset _activePreset = AppMotionPreset.fadeScale;
  int _motionReplayKey = 0;
  bool _aiThinking = false;
  _ShowcaseTab _tab = _ShowcaseTab.foundations;

  static const _colorPairs = [
    _ColorPair('Primary text', '#1A2029', '#FAFBFC', '#E6EBF2', '#0E1116'),
    _ColorPair('Secondary text', '#55606D', '#FAFBFC', '#A9B4C0', '#0E1116'),
    _ColorPair('Action primary', '#FFFFFF', '#0B7075', '#0E1116', '#0E8A8F'),
    _ColorPair('AI action', '#FFFFFF', '#573FD1', '#0E1116', '#6A54E6'),
    _ColorPair('Success', '#0F5E34', '#E7F6ED', '#5FD495', '#0E2A1B'),
    _ColorPair('Warning', '#855009', '#FBF1DF', '#E9B45A', '#2E2109'),
    _ColorPair('Danger', '#9A2828', '#FBECEC', '#F08A8A', '#2E1414'),
    _ColorPair('Info', '#164FAB', '#E8F0FE', '#7FB0FB', '#0F1F3A'),
  ];

  static const _foundationSections = [
    ('colors', 'Color'),
    ('typography', 'Typography'),
    ('spacing', 'Spacing & elevation'),
    ('motion', 'Motion'),
    ('signal', 'The Signal'),
  ];

  void _replayMotion() => setState(() => _motionReplayKey++);

  bool get _isDark {
    final mode = ref.watch(themeModeProvider);
    if (mode == ThemeMode.dark) return true;
    if (mode == ThemeMode.light) return false;
    return WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final elevation = context.elevation;
    final localeState = ref.watch(appLocaleProvider);
    final isArabic = localeState.locale == AppLocale.ar;
    final reducedMotion = ref.watch(reducedMotionProvider);

    return Scaffold(
      backgroundColor: colors.surfaceCanvas,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: colors.surfaceDefault.withValues(alpha: 0.95),
            surfaceTintColor: Colors.transparent,
            leading: context.canPop()
                ? IconButton(icon: const Icon(Icons.arrow_back), tooltip: 'Back', onPressed: () => context.pop())
                : null,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Design reference', style: typography.overline.copyWith(color: colors.textTertiary)),
                Text('Design System', style: typography.h1.copyWith(color: colors.textPrimary)),
              ],
            ),
            actions: [_ShowcaseControls(isDark: _isDark)],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(1),
              child: Divider(height: 1, color: colors.borderSubtle),
            ),
          ),
          SliverToBoxAdapter(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1024),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s6, vertical: AppSpacing.s10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _tab == _ShowcaseTab.foundations
                            ? 'Calm Clinical Precision — the design system foundation for AiClinic. '
                                  'Tokens, typography, motion, and The Signal.'
                            : 'Shared primitives with full variant and state matrices. '
                                  'Toggle theme, locale, reduced motion, and density in the header.',
                        style: typography.bodyLg.copyWith(color: colors.textSecondary),
                      ),
                      const SizedBox(height: AppSpacing.s6),
                      Text(
                        _tab == _ShowcaseTab.foundations ? 'Foundations' : 'Components',
                        style: typography.h2.copyWith(color: colors.textPrimary),
                      ),
                      const SizedBox(height: AppSpacing.s4),
                      Wrap(
                        spacing: AppSpacing.s2,
                        runSpacing: AppSpacing.s2,
                        children: [
                          ChoiceChip(
                            label: Text(
                              'Foundations',
                              style: typography.bodySm.copyWith(
                                color: _tab == _ShowcaseTab.foundations ? colors.textPrimary : colors.textLink,
                              ),
                            ),
                            selected: _tab == _ShowcaseTab.foundations,
                            onSelected: (_) => setState(() => _tab = _ShowcaseTab.foundations),
                          ),
                          ChoiceChip(
                            label: Text(
                              'Components',
                              style: typography.bodySm.copyWith(
                                color: _tab == _ShowcaseTab.components ? colors.textPrimary : colors.textLink,
                              ),
                            ),
                            selected: _tab == _ShowcaseTab.components,
                            onSelected: (_) => setState(() => _tab = _ShowcaseTab.components),
                          ),
                        ],
                      ),
                      if (_tab == _ShowcaseTab.foundations) ...[
                        const SizedBox(height: AppSpacing.s4),
                        Wrap(
                          spacing: AppSpacing.s2,
                          runSpacing: AppSpacing.s2,
                          children: _foundationSections
                              .map(
                                (s) => ActionChip(
                                  label: Text(s.$2, style: typography.bodySm.copyWith(color: colors.textLink)),
                                  onPressed: () {},
                                ),
                              )
                              .toList(),
                        ),
                        const SizedBox(height: AppSpacing.s16),
                        _Section(
                          title: 'Color',
                          description: 'Semantic pairs with WCAG 2.2 AA contrast verification in both themes.',
                          child: _ColorSection(
                            isDark: _isDark,
                            colors: colors,
                            typography: typography,
                            elevation: elevation,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.s16),
                        _Section(
                          title: 'Typography',
                          description:
                              'Inter + Geist for Latin; IBM Plex Sans Arabic on :lang(ar). Tabular nums for data.',
                          child: _TypographySection(isArabic: isArabic, colors: colors, typography: typography),
                        ),
                        const SizedBox(height: AppSpacing.s16),
                        _Section(
                          title: 'Spacing, Radius & Elevation',
                          description:
                              '4px base unit. Elevation is border + soft shadow — kept cheap for low-end hardware.',
                          child: _SpacingSection(colors: colors, typography: typography, elevation: elevation),
                        ),
                        const SizedBox(height: AppSpacing.s16),
                        _Section(
                          title: 'Motion',
                          description: 'Presets from 03-motion. Respects prefers-reduced-motion.',
                          child: _MotionSection(
                            activePreset: _activePreset,
                            replayKey: _motionReplayKey,
                            reducedMotion: reducedMotion,
                            colors: colors,
                            typography: typography,
                            onPresetSelected: (preset) {
                              setState(() {
                                _activePreset = preset;
                                _motionReplayKey++;
                              });
                            },
                            onReplay: _replayMotion,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.s16),
                        _Section(
                          title: 'The Signal',
                          description: 'Signature primitive — active nav, Command Bar focus, AI thinking pulse.',
                          child: _SignalSection(
                            aiThinking: _aiThinking,
                            colors: colors,
                            typography: typography,
                            onToggleThinking: () => setState(() => _aiThinking = !_aiThinking),
                          ),
                        ),
                      ] else ...[
                        const SizedBox(height: AppSpacing.s10),
                        const ComponentsShowcase(),
                      ],
                      const SizedBox(height: AppSpacing.s10),
                      Center(
                        child: Text(
                          'AiClinic Design System · Flutter · presentation only',
                          style: typography.caption.copyWith(color: colors.textTertiary),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShowcaseControls extends ConsumerWidget {
  const _ShowcaseControls({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localeState = ref.watch(appLocaleProvider);
    final reducedMotion = ref.watch(reducedMotionProvider);
    final density = ref.watch(appDensityProvider);
    final typography = context.typography;
    final colors = context.colors;

    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.s4),
      child: Wrap(
        spacing: AppSpacing.s2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _ControlChip(
            label: isDark ? 'Dark' : 'Light',
            onPressed: () => setAppThemeMode(ref, isDark ? ThemeMode.light : ThemeMode.dark),
            typography: typography,
            colors: colors,
          ),
          _ControlChip(
            label: localeState.locale == AppLocale.ar ? 'AR / RTL' : 'EN / LTR',
            onPressed: () => ref.read(appLocaleProvider.notifier).toggleLocale(),
            typography: typography,
            colors: colors,
          ),
          _ControlChip(
            label: reducedMotion ? 'Reduced motion' : 'Motion on',
            onPressed: () => ref.read(reducedMotionProvider.notifier).toggle(),
            typography: typography,
            colors: colors,
          ),
          _ControlChip(
            label: density.label,
            onPressed: () => ref.read(appDensityProvider.notifier).cycle(),
            typography: typography,
            colors: colors,
          ),
        ],
      ),
    );
  }
}

class _ControlChip extends StatelessWidget {
  const _ControlChip({required this.label, required this.onPressed, required this.typography, required this.colors});

  final String label;
  final VoidCallback onPressed;
  final AppTypography typography;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s3, vertical: AppSpacing.s1),
        side: BorderSide(color: colors.borderDefault),
        foregroundColor: colors.textPrimary,
        textStyle: typography.bodySm,
      ),
      child: Text(label),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, this.description, required this.child});

  final String title;
  final String? description;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: colors.borderSubtle)),
          ),
          child: Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.s4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: typography.h2.copyWith(color: colors.textPrimary)),
                if (description != null) ...[
                  const SizedBox(height: AppSpacing.s1),
                  Text(description!, style: typography.body.copyWith(color: colors.textSecondary)),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.s6),
        child,
      ],
    );
  }
}

class _ColorSection extends StatelessWidget {
  const _ColorSection({required this.isDark, required this.colors, required this.typography, required this.elevation});

  final bool isDark;
  final AppColors colors;
  final AppTypography typography;
  final AppElevation elevation;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final crossCount = constraints.maxWidth > 800
                ? 4
                : constraints.maxWidth > 500
                ? 2
                : 1;
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossCount,
                mainAxisSpacing: AppSpacing.s4,
                crossAxisSpacing: AppSpacing.s4,
                childAspectRatio: 1.6,
              ),
              itemCount: _DesignSystemShowcasePageState._colorPairs.length,
              itemBuilder: (context, index) {
                final pair = _DesignSystemShowcasePageState._colorPairs[index];
                final fgHex = isDark ? pair.darkFg : pair.fg;
                final bgHex = isDark ? pair.darkBg : pair.bg;
                final ratio = AppContrast.contrastRatioHex(fgHex, bgHex);
                final pass = AppContrast.meetsAA(ratio);
                return DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: AppRadius.lgAll,
                    border: Border.all(color: colors.borderDefault),
                    boxShadow: elevation.level1,
                  ),
                  child: ClipRRect(
                    borderRadius: AppRadius.lgAll,
                    child: Column(
                      children: [
                        Expanded(
                          child: ColoredBox(
                            color: AppContrast.hexToColor(bgHex),
                            child: Center(
                              child: Text(
                                pair.label,
                                style: typography.bodyStrong.copyWith(color: AppContrast.hexToColor(fgHex)),
                              ),
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s3, vertical: AppSpacing.s2),
                          color: colors.surfaceDefault,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                AppContrast.formatContrast(ratio),
                                style: typography.caption.copyWith(color: colors.textTertiary),
                              ),
                              Text(
                                pass ? 'AA ✓' : 'Fail',
                                style: typography.caption.copyWith(
                                  color: pass ? colors.statusSuccessFg : colors.statusDangerFg,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
        const SizedBox(height: AppSpacing.s8),
        LayoutBuilder(
          builder: (context, constraints) {
            final crossCount = constraints.maxWidth > 800
                ? 4
                : constraints.maxWidth > 500
                ? 2
                : 1;
            final swatches = <_SurfaceSwatch>[
              _SurfaceSwatch('Canvas', colors.surfaceCanvas),
              _SurfaceSwatch('Default', colors.surfaceDefault),
              _SurfaceSwatch('Raised', colors.surfaceRaised, shadows: elevation.level1),
              _SurfaceSwatch('Sunken', colors.surfaceSunken),
              _SurfaceSwatch('Muted', colors.surfaceMuted),
              _SurfaceSwatch('Selected', colors.surfaceSelected),
              _SurfaceSwatch('AI surface', colors.surfaceAi),
              _SurfaceSwatch('Action primary', colors.actionPrimary),
            ];
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossCount,
                mainAxisSpacing: AppSpacing.s4,
                crossAxisSpacing: AppSpacing.s4,
                childAspectRatio: 2.2,
              ),
              itemCount: swatches.length,
              itemBuilder: (context, index) {
                final swatch = swatches[index];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: swatch.color,
                          borderRadius: AppRadius.lgAll,
                          border: Border.all(color: colors.borderSubtle),
                          boxShadow: swatch.shadows,
                        ),
                        child: const SizedBox.expand(),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s2),
                    Text(swatch.label, style: typography.caption.copyWith(color: colors.textTertiary)),
                  ],
                );
              },
            );
          },
        ),
      ],
    );
  }
}

class _TypographySection extends StatelessWidget {
  const _TypographySection({required this.isArabic, required this.colors, required this.typography});

  final bool isArabic;
  final AppColors colors;
  final AppTypography typography;

  @override
  Widget build(BuildContext context) {
    final samples = isArabic
        ? (
            display: 'نظام العيادة',
            h1: 'سجل المرضى',
            body: 'تسجيل مريض جديد وإدارة المواعيد والفواتير.',
            mono: 'INV-2026-00482',
            data: '١٬٢٥٠٫٠٠ ج.م',
            n36: '٣٦',
            time: '١٤:٣٠',
          )
        : (
            display: 'Clinic Console',
            h1: 'Patient Registry',
            body: 'Register patients, manage appointments, and issue invoices.',
            mono: 'INV-2026-00482',
            data: 'EGP 1,250.00',
            n36: '36',
            time: '14:30',
          );

    final scaleEntries = [
      (typography.displayLg, 'display-lg', '32/40'),
      (typography.display, 'display', '28/36'),
      (typography.h1, 'h1', '24/32'),
      (typography.h2, 'h2', '20/28'),
      (typography.h3, 'h3', '18/26'),
      (typography.title, 'title', '16/24'),
      (typography.bodyLg, 'body-lg', '15/24'),
      (typography.body, 'body', '14/22'),
      (typography.bodySm, 'body-sm', '13/20'),
      (typography.caption, 'caption', '12/16'),
      (typography.overline, 'overline', '11/16'),
      (typography.mono, 'mono', '13/20'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: AppRadius.lgAll,
            border: Border.all(color: colors.borderDefault),
            color: colors.surfaceDefault,
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.s6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _TypeSample(
                  label: 'Display LG',
                  style: typography.displayLg,
                  text: samples.display,
                  colors: colors,
                  typography: typography,
                ),
                _TypeSample(
                  label: 'H1',
                  style: typography.h1,
                  text: samples.h1,
                  colors: colors,
                  typography: typography,
                ),
                _TypeSample(
                  label: 'Body',
                  style: typography.body,
                  text: samples.body,
                  colors: colors,
                  typography: typography,
                  textColor: colors.textSecondary,
                ),
                _TypeSample(
                  label: 'Mono / IDs',
                  style: typography.mono,
                  text: samples.mono,
                  colors: colors,
                  typography: typography,
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Tabular data', style: typography.overline.copyWith(color: colors.textTertiary)),
                    const SizedBox(height: AppSpacing.s2),
                    Row(
                      children: [
                        Text(
                          samples.data,
                          style: typography.h2.copyWith(
                            color: colors.textPrimary,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(width: AppSpacing.s8),
                        Text(
                          samples.n36,
                          style: typography.h2.copyWith(
                            color: colors.textPrimary,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(width: AppSpacing.s8),
                        Text(
                          samples.time,
                          style: typography.h2.copyWith(
                            color: colors.textPrimary,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.s6),
        LayoutBuilder(
          builder: (context, constraints) {
            final crossCount = constraints.maxWidth > 500 ? 2 : 1;
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossCount,
                mainAxisSpacing: AppSpacing.s3,
                crossAxisSpacing: AppSpacing.s3,
                childAspectRatio: 3.5,
              ),
              itemCount: scaleEntries.length,
              itemBuilder: (context, index) {
                final (style, name, size) = scaleEntries[index];
                return DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: AppRadius.mdAll,
                    border: Border.all(color: colors.borderSubtle),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s4, vertical: AppSpacing.s3),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Aa', style: style.copyWith(color: colors.textPrimary)),
                        Text('$name · $size', style: typography.caption.copyWith(color: colors.textTertiary)),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }
}

class _TypeSample extends StatelessWidget {
  const _TypeSample({
    required this.label,
    required this.style,
    required this.text,
    required this.colors,
    required this.typography,
    this.textColor,
  });

  final String label;
  final TextStyle style;
  final String text;
  final AppColors colors;
  final AppTypography typography;
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: typography.overline.copyWith(color: colors.textTertiary)),
          const SizedBox(height: AppSpacing.s2),
          Text(text, style: style.copyWith(color: textColor ?? colors.textPrimary)),
        ],
      ),
    );
  }
}

class _SpacingSection extends StatelessWidget {
  const _SpacingSection({required this.colors, required this.typography, required this.elevation});

  final AppColors colors;
  final AppTypography typography;
  final AppElevation elevation;

  static const _spacingTokens = [
    ('0', AppSpacing.s0),
    ('px', AppSpacing.px),
    ('0.5', AppSpacing.s0_5),
    ('1', AppSpacing.s1),
    ('2', AppSpacing.s2),
    ('3', AppSpacing.s3),
    ('4', AppSpacing.s4),
    ('5', AppSpacing.s5),
    ('6', AppSpacing.s6),
    ('8', AppSpacing.s8),
    ('10', AppSpacing.s10),
    ('12', AppSpacing.s12),
    ('16', AppSpacing.s16),
    ('20', AppSpacing.s20),
    ('24', AppSpacing.s24),
  ];

  static const _radiusTokens = [
    ('sm', AppRadius.sm),
    ('md', AppRadius.md),
    ('lg', AppRadius.lg),
    ('xl', AppRadius.xl),
    ('2xl', AppRadius.xxl),
    ('full', AppRadius.full),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Spacing', style: typography.h3.copyWith(color: colors.textPrimary)),
        const SizedBox(height: AppSpacing.s4),
        Wrap(
          spacing: AppSpacing.s4,
          runSpacing: AppSpacing.s4,
          crossAxisAlignment: WrapCrossAlignment.end,
          children: _spacingTokens.map((token) {
            return Column(
              children: [
                Container(width: token.$2 == 0 ? 1 : token.$2, height: 24, color: colors.actionPrimary),
                const SizedBox(height: AppSpacing.s2),
                Text('space-${token.$1}', style: typography.caption.copyWith(color: colors.textTertiary)),
              ],
            );
          }).toList(),
        ),
        const SizedBox(height: AppSpacing.s10),
        Text('Radius', style: typography.h3.copyWith(color: colors.textPrimary)),
        const SizedBox(height: AppSpacing.s4),
        LayoutBuilder(
          builder: (context, constraints) {
            final crossCount = constraints.maxWidth > 700
                ? 6
                : constraints.maxWidth > 400
                ? 3
                : 2;
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossCount,
                mainAxisSpacing: AppSpacing.s4,
                crossAxisSpacing: AppSpacing.s4,
                childAspectRatio: 1.2,
              ),
              itemCount: _radiusTokens.length,
              itemBuilder: (context, index) {
                final (name, radius) = _radiusTokens[index];
                return Column(
                  children: [
                    Expanded(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: colors.surfaceMuted,
                          borderRadius: BorderRadius.circular(radius > 100 ? 16 : radius),
                          border: Border.all(color: colors.actionPrimary, width: 2),
                        ),
                        child: const SizedBox.expand(),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s2),
                    Text('radius-$name', style: typography.caption.copyWith(color: colors.textTertiary)),
                  ],
                );
              },
            );
          },
        ),
        const SizedBox(height: AppSpacing.s10),
        Text('Elevation', style: typography.h3.copyWith(color: colors.textPrimary)),
        const SizedBox(height: AppSpacing.s4),
        LayoutBuilder(
          builder: (context, constraints) {
            final crossCount = constraints.maxWidth > 700
                ? 4
                : constraints.maxWidth > 400
                ? 2
                : 1;
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossCount,
                mainAxisSpacing: AppSpacing.s6,
                crossAxisSpacing: AppSpacing.s6,
                childAspectRatio: 2.5,
              ),
              itemCount: 4,
              itemBuilder: (context, index) {
                return DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: AppRadius.lgAll,
                    border: Border.all(color: colors.borderSubtle),
                    color: colors.surfaceDefault,
                    boxShadow: elevation.level(index),
                  ),
                  child: Center(
                    child: Text('elevation-$index', style: typography.bodyStrong.copyWith(color: colors.textSecondary)),
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }
}

class _MotionSection extends StatelessWidget {
  const _MotionSection({
    required this.activePreset,
    required this.replayKey,
    required this.reducedMotion,
    required this.colors,
    required this.typography,
    required this.onPresetSelected,
    required this.onReplay,
  });

  final AppMotionPreset activePreset;
  final int replayKey;
  final bool reducedMotion;
  final AppColors colors;
  final AppTypography typography;
  final ValueChanged<AppMotionPreset> onPresetSelected;
  final VoidCallback onReplay;

  static const _presets = [
    AppMotionPreset.fade,
    AppMotionPreset.fadeScale,
    AppMotionPreset.slideUp,
    AppMotionPreset.slideInline,
    AppMotionPreset.modal,
    AppMotionPreset.command,
    AppMotionPreset.rowEnter,
  ];

  @override
  Widget build(BuildContext context) {
    final elevation = context.elevation;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AppSpacing.s2,
          runSpacing: AppSpacing.s2,
          children: [
            ..._presets.map((preset) {
              final selected = preset == activePreset;
              return TextButton(
                onPressed: () => onPresetSelected(preset),
                style: TextButton.styleFrom(
                  backgroundColor: selected ? colors.surfaceSelected : colors.surfaceMuted,
                  foregroundColor: selected ? colors.textPrimary : colors.textSecondary,
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s3, vertical: AppSpacing.s1 + 2),
                  shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
                ),
                child: Text('motion-${preset.name}', style: typography.bodySm),
              );
            }),
            OutlinedButton(
              onPressed: onReplay,
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: colors.borderDefault),
                foregroundColor: colors.textPrimary,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s3, vertical: AppSpacing.s1 + 2),
              ),
              child: Text('Replay', style: typography.bodySm),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s6),
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: AppRadius.lgAll,
            border: Border.all(color: colors.borderDefault),
            color: colors.surfaceSunken,
          ),
          child: SizedBox(
            height: 192,
            child: Center(
              child: AppMotionPresetAnimator(
                key: ValueKey('$activePreset-$replayKey'),
                preset: activePreset,
                replayKey: replayKey,
                reducedMotion: reducedMotion,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: AppRadius.lgAll,
                    color: colors.surfaceDefault,
                    boxShadow: elevation.level2,
                  ),
                  child: SizedBox(
                    width: 192,
                    height: 96,
                    child: Center(
                      child: Text(activePreset.name, style: typography.bodyStrong.copyWith(color: colors.textPrimary)),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.s6),
        Text('Staggered row enter (≤5)', style: typography.overline.copyWith(color: colors.textTertiary)),
        const SizedBox(height: AppSpacing.s3),
        _StaggeredRows(reducedMotion: reducedMotion, colors: colors, typography: typography),
      ],
    );
  }
}

class _StaggeredRows extends StatefulWidget {
  const _StaggeredRows({required this.reducedMotion, required this.colors, required this.typography});

  final bool reducedMotion;
  final AppColors colors;
  final AppTypography typography;

  @override
  State<_StaggeredRows> createState() => _StaggeredRowsState();
}

class _StaggeredRowsState extends State<_StaggeredRows> {
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => setState(() => _generation++));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(5, (index) {
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.s2),
          child: TweenAnimationBuilder<double>(
            key: ValueKey('row-$_generation-$index'),
            tween: Tween(begin: 0, end: 1),
            duration:
                AppMotion.resolveTransition(
                  preset: AppMotionPreset.rowEnter,
                  reducedMotion: widget.reducedMotion,
                ).duration +
                AppMotion.staggerDelay(index),
            curve: AppMotion.resolveTransition(
              preset: AppMotionPreset.rowEnter,
              reducedMotion: widget.reducedMotion,
            ).curve,
            builder: (context, t, child) {
              final hidden = AppMotion.hiddenValues(AppMotionPreset.rowEnter, direction: Directionality.of(context));
              final values = hidden.lerp(AppMotion.visibleValues, t);
              return Opacity(
                opacity: values.opacity,
                child: Transform.translate(offset: Offset(0, values.dy), child: child),
              );
            },
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: AppRadius.mdAll,
                border: Border.all(color: widget.colors.borderSubtle),
                color: widget.colors.surfaceDefault,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s4, vertical: AppSpacing.s2),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    'Row ${index + 1}',
                    style: widget.typography.body.copyWith(color: widget.colors.textSecondary),
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _SignalSection extends StatelessWidget {
  const _SignalSection({
    required this.aiThinking,
    required this.colors,
    required this.typography,
    required this.onToggleThinking,
  });

  final bool aiThinking;
  final AppColors colors;
  final AppTypography typography;
  final VoidCallback onToggleThinking;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 700;
        return Flex(
          direction: isWide ? Axis.horizontal : Axis.vertical,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: AppRadius.lgAll,
                  border: Border.all(color: colors.borderDefault),
                  color: colors.surfaceDefault,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.s6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Standard (teal)', style: typography.overline.copyWith(color: colors.textTertiary)),
                      const SizedBox(height: AppSpacing.s4),
                      SizedBox(
                        height: 56,
                        child: Stack(
                          children: [
                            const PositionedDirectional(
                              start: 0,
                              top: 8,
                              bottom: 8,
                              child: Signal(orientation: SignalOrientation.vertical),
                            ),
                            Padding(
                              padding: const EdgeInsetsDirectional.only(start: AppSpacing.s4 + 4),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Active navigation item',
                                    style: typography.bodyStrong.copyWith(color: colors.textPrimary),
                                  ),
                                  const SizedBox(height: AppSpacing.s1),
                                  Text('Patients', style: typography.caption.copyWith(color: colors.textTertiary)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.s6),
                      Text('Horizontal · hero', style: typography.caption.copyWith(color: colors.textTertiary)),
                      const SizedBox(height: AppSpacing.s2),
                      const SizedBox(width: 280, child: Signal(size: SignalSize.hero)),
                    ],
                  ),
                ),
              ),
            ),
            SizedBox(width: isWide ? AppSpacing.s8 : 0, height: isWide ? 0 : AppSpacing.s8),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: AppRadius.lgAll,
                  border: Border.all(color: colors.borderAi),
                  color: colors.surfaceAi,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.s6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('AI (violet)', style: typography.overline.copyWith(color: colors.textAi)),
                      const SizedBox(height: AppSpacing.s4),
                      Signal(variant: SignalVariant.ai, thinking: aiThinking),
                      const SizedBox(height: AppSpacing.s4),
                      Text('AI is drafting a proposed action…', style: typography.body.copyWith(color: colors.textAi)),
                      const SizedBox(height: AppSpacing.s4),
                      FilledButton(
                        onPressed: onToggleThinking,
                        style: FilledButton.styleFrom(
                          backgroundColor: colors.actionAi,
                          foregroundColor: colors.actionAiFg,
                        ),
                        child: Text(aiThinking ? 'Stop pulse' : 'Start thinking pulse', style: typography.bodyStrong),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ColorPair {
  const _ColorPair(this.label, this.fg, this.bg, this.darkFg, this.darkBg);
  final String label;
  final String fg;
  final String bg;
  final String darkFg;
  final String darkBg;
}

class _SurfaceSwatch {
  const _SurfaceSwatch(this.label, this.color, {this.shadows});
  final String label;
  final Color color;
  final List<BoxShadow>? shadows;
}
