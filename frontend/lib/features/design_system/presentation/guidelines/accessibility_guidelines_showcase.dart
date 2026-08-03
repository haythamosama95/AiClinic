import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/components/app_button.dart';
import 'package:ai_clinic/core/ui/components/app_kbd.dart';
import 'package:ai_clinic/core/ui/components/app_signal.dart';
import 'package:ai_clinic/core/ui/components/app_switch.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
import 'package:ai_clinic/features/design_system/presentation/foundations/dev_section_link.dart';
import 'package:ai_clinic/features/design_system/presentation/widgets/showcase_primitives.dart';

class _KeyboardRow {
  const _KeyboardRow({required this.keys, required this.action});

  final List<String> keys;
  final String action;
}

const _keyboardMap = <_KeyboardRow>[
  _KeyboardRow(keys: ['⌘', 'K'], action: 'Open Command Bar'),
  _KeyboardRow(keys: ['/'], action: 'Focus page search'),
  _KeyboardRow(keys: ['Esc'], action: 'Close topmost overlay'),
  _KeyboardRow(keys: ['Tab'], action: 'Move focus forward'),
  _KeyboardRow(keys: ['Shift', 'Tab'], action: 'Move focus backward'),
  _KeyboardRow(keys: ['Enter'], action: 'Activate focused control'),
];

class _ContrastPair {
  const _ContrastPair({required this.token, required this.fg, required this.bg, required this.ratio});

  final String token;
  final Color Function(AppSemanticColors colors) fg;
  final Color Function(AppSemanticColors colors) bg;
  final String ratio;
}

/// Accessibility guidelines (web `AccessibilityGuidelinesShowcase`).
class AccessibilityGuidelinesShowcase extends StatefulWidget {
  const AccessibilityGuidelinesShowcase({super.key});

  @override
  State<AccessibilityGuidelinesShowcase> createState() => _AccessibilityGuidelinesShowcaseState();
}

class _AccessibilityGuidelinesShowcaseState extends State<AccessibilityGuidelinesShowcase> {
  var _reducedMotion = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    final contrastPairs = <_ContrastPair>[
      _ContrastPair(
        token: 'text-primary on surface-default',
        fg: (c) => c.textPrimary,
        bg: (c) => c.surfaceDefault,
        ratio: '12.4:1',
      ),
      _ContrastPair(
        token: 'text-secondary on surface-default',
        fg: (c) => c.textSecondary,
        bg: (c) => c.surfaceDefault,
        ratio: '7.1:1',
      ),
      _ContrastPair(
        token: 'action-primary-fg on action-primary',
        fg: (c) => c.actionPrimaryFg,
        bg: (c) => c.actionPrimary,
        ratio: '4.8:1',
      ),
      _ContrastPair(token: 'text-ai on surface-ai', fg: (c) => c.textAi, bg: (c) => c.surfaceAi, ratio: '5.2:1'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ShowcaseSection(
          id: 'guidelines-focus',
          title: 'Visible focus',
          componentName: '07 §2 Keyboard',
          description:
              'Focus ring is always visible. Tab through this section to see focus-ring on interactive elements.',
          child: Wrap(
            spacing: AppSpacing.space3,
            runSpacing: AppSpacing.space3,
            children: [
              AppButton(variant: AppButtonVariant.primary, onPressed: () {}, child: const Text('Primary')),
              AppButton(variant: AppButtonVariant.secondary, onPressed: () {}, child: const Text('Secondary')),
              AppButton(variant: AppButtonVariant.ghost, onPressed: () {}, child: const Text('Ghost')),
              DevSectionLink(
                sectionId: 'guidelines-contrast',
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space3, vertical: AppSpacing.space2),
                child: const Text('Skip to contrast'),
              ),
            ],
          ),
        ),
        ShowcaseSection(
          id: 'guidelines-contrast',
          title: 'Contrast',
          componentName: '07 §1 Color & contrast',
          description: 'Semantic token pairs verified for WCAG 2.2 AA in light and dark themes.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 640;
                  final tiles = contrastPairs.map((pair) => _ContrastTile(pair: pair)).toList();
                  if (isWide) {
                    return Wrap(
                      spacing: AppSpacing.space3,
                      runSpacing: AppSpacing.space3,
                      children: tiles
                          .map((tile) => SizedBox(width: (constraints.maxWidth - AppSpacing.space3) / 2, child: tile))
                          .toList(),
                    );
                  }
                  return Column(
                    children: [
                      for (final tile in tiles) ...[tile, const SizedBox(height: AppSpacing.space3)],
                    ],
                  );
                },
              ),
              const SizedBox(height: AppSpacing.space4),
              Text(
                'Status always pairs color with text and/or icon — never color alone.',
                style: AppTypography.bodySm(context).copyWith(color: colors.textSecondary),
              ),
            ],
          ),
        ),
        ShowcaseSection(
          id: 'guidelines-keyboard',
          title: 'Keyboard map',
          componentName: '07 §2 Shortcuts',
          description: 'Discoverable shortcuts that never replace mouse/touch paths.',
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: colors.borderDefault),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              child: Table(
                columnWidths: const {0: FlexColumnWidth(), 1: FlexColumnWidth(2)},
                children: [
                  TableRow(
                    decoration: BoxDecoration(color: colors.surfaceSunken),
                    children: [_TableHeadCell('Shortcut'), _TableHeadCell('Action')],
                  ),
                  for (final row in _keyboardMap)
                    TableRow(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(AppSpacing.space4),
                          child: AppKbd(keys: row.keys),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(AppSpacing.space4),
                          child: Text(row.action, style: AppTypography.bodySm(context)),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
        ShowcaseSection(
          id: 'guidelines-reduced-motion',
          title: 'Reduced motion',
          componentName: '07 §4 Motion',
          description: 'Honors OS setting plus manual override. Loops and shimmer stop under reduced motion.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: AppSpacing.space6,
                runSpacing: AppSpacing.space4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppSwitch(value: _reducedMotion, onChanged: (value) => setState(() => _reducedMotion = value)),
                      const SizedBox(width: AppSpacing.space3),
                      Text('Reduce motion', style: AppTypography.body(context)),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _SignalPreview(
                        label: 'Teal (deterministic)',
                        variant: AppSignalVariant.standard,
                        thinking: !_reducedMotion,
                      ),
                      const SizedBox(width: AppSpacing.space4),
                      _SignalPreview(label: 'Violet (AI)', variant: AppSignalVariant.ai, thinking: !_reducedMotion),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.space4),
              Text(
                'Under reduced motion: pulse stops, drawer blur disabled, skeleton shimmer static.',
                style: AppTypography.bodySm(context).copyWith(color: colors.textSecondary),
              ),
            ],
          ),
        ),
        const _GuidelinesListSection(
          id: 'guidelines-ai-a11y',
          title: 'AI accessibility',
          componentName: '07 §6 AI-specific',
          description: 'AI distinction conveyed by label and text, not violet color alone.',
          items: [
            'Proposed Action Cards are fully keyboard operable with named Approve / Edit / Dismiss buttons.',
            'Streaming responses use polite live regions — not per-token announcements.',
            '"Proposed by AI" label is always visible on actionable AI output.',
            'Human approval is required before any write — never implied by AI copy alone.',
          ],
        ),
        const _GuidelinesListSection(
          id: 'guidelines-i18n',
          title: 'Internationalization',
          componentName: '07 §7 i18n',
          description: 'Use Dev controls above to verify EN/LTR and AR/RTL.',
          items: [
            'Logical properties mirror layout and directional icons in RTL.',
            'Arabic uses IBM Plex Sans Arabic with adjusted line-height.',
            'Components tolerate text expansion without clipping.',
            'Money and dates use locale-aware formatting with Western digits.',
          ],
        ),
      ],
    );
  }
}

class _ContrastTile extends StatelessWidget {
  const _ContrastTile({required this.pair});

  final _ContrastPair pair;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: pair.bg(colors),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.space4),
        child: Row(
          children: [
            Expanded(
              child: Text(pair.token, style: AppTypography.bodyStrong(context).copyWith(color: pair.fg(colors))),
            ),
            Text(
              pair.ratio,
              style: AppTypography.caption(context).copyWith(fontFamily: 'JetBrains Mono', color: colors.textTertiary),
            ),
          ],
        ),
      ),
    );
  }
}

class _TableHeadCell extends StatelessWidget {
  const _TableHeadCell(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.space2),
      child: Text(
        text,
        style: AppTypography.bodySm(
          context,
        ).copyWith(fontWeight: FontWeight.w500, color: context.appColors.textSecondary),
      ),
    );
  }
}

class _SignalPreview extends StatelessWidget {
  const _SignalPreview({required this.label, required this.variant, required this.thinking});

  final String label;
  final AppSignalVariant variant;
  final bool thinking;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: AppTypography.caption(context).copyWith(color: context.appColors.textTertiary)),
        const SizedBox(height: AppSpacing.space2),
        AppSignal(variant: variant, active: true, thinking: thinking),
      ],
    );
  }
}

class _GuidelinesListSection extends StatelessWidget {
  const _GuidelinesListSection({
    required this.id,
    required this.title,
    required this.componentName,
    required this.description,
    required this.items,
  });

  final String id;
  final String title;
  final String componentName;
  final String description;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return ShowcaseSection(
      id: id,
      title: title,
      componentName: componentName,
      description: description,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.space2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('• ', style: AppTypography.body(context).copyWith(color: context.appColors.textSecondary)),
                  Expanded(
                    child: Text(
                      item,
                      style: AppTypography.body(context).copyWith(color: context.appColors.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
