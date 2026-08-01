import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
import 'package:ai_clinic/features/design_system/presentation/widgets/showcase_primitives.dart';
import 'package:ai_clinic/features/design_system/presentation/widgets/dev_text_styles.dart';

class _CopyExample {
  const _CopyExample({required this.context, required this.good, required this.avoid});

  final String context;
  final String good;
  final String avoid;
}

const _voiceExamples = <_CopyExample>[
  _CopyExample(context: 'Primary button', good: 'Add service', avoid: 'Submit'),
  _CopyExample(context: 'Destructive confirmation', good: 'Delete service', avoid: 'Yes'),
  _CopyExample(
    context: 'Empty state',
    good: 'No services yet. Add your first service to start billing.',
    avoid: 'No data found.',
  ),
  _CopyExample(
    context: 'Validation error',
    good: 'The promotion must be less than or equal to the effective price.',
    avoid: 'PROMO_EXCEEDS_PRICE',
  ),
  _CopyExample(
    context: 'Concurrency conflict',
    good: 'This was changed by someone else. Reload to see the latest version before saving.',
    avoid: 'STALE_SERVICE error.',
  ),
  _CopyExample(
    context: 'AI proposal',
    good: 'AI suggests booking a follow-up for Layla Hassan.',
    avoid: 'Appointment booked for Layla Hassan.',
  ),
  _CopyExample(
    context: 'AI unavailable',
    good: 'AI is unavailable right now. You can do this manually.',
    avoid: 'Error: AI service down.',
  ),
  _CopyExample(context: 'Permission denied', good: "You don't have permission to do this.", avoid: '403 Forbidden'),
];

/// Voice & content guidelines (web `VoiceGuidelinesShowcase`).
class VoiceGuidelinesShowcase extends StatelessWidget {
  const VoiceGuidelinesShowcase({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return ShowcaseSection(
      id: 'guidelines-voice',
      title: 'Voice & content',
      componentName: '08-voice-and-content',
      description: 'Good vs avoid copy for buttons, errors, empties, confirmations, and AI.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final example in _voiceExamples) ...[
            Text(example.context, style: AppTypography.bodyStrong(context)),
            const SizedBox(height: AppSpacing.space3),
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 640;
                final children = [
                  _CopyCard(label: 'Use', text: example.good, variant: _CopyVariant.good),
                  _CopyCard(label: 'Avoid', text: example.avoid, variant: _CopyVariant.avoid),
                ];
                if (isWide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: children[0]),
                      const SizedBox(width: AppSpacing.space4),
                      Expanded(child: children[1]),
                    ],
                  );
                }
                return Column(
                  children: [
                    children[0],
                    const SizedBox(height: AppSpacing.space4),
                    children[1],
                  ],
                );
              },
            ),
            const SizedBox(height: AppSpacing.space8),
          ],
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surfaceSunken,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: colors.borderDefault),
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.space6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('House rules', style: DevTextStyles.h3(context)),
                  const SizedBox(height: AppSpacing.space3),
                  _HouseRule('Sentence case everywhere — buttons, titles, labels.'),
                  _HouseRule('Verb-first actions: "Save changes", not "OK".'),
                  _HouseRule('One name per concept: if the button says "Publish", the toast says "Published".'),
                  _HouseRule('Tabular figures for money, dates, and counts.'),
                  _HouseRule('Write whole phrases for translation — no string concatenation.'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _CopyVariant { good, avoid }

class _CopyCard extends StatelessWidget {
  const _CopyCard({required this.label, required this.text, required this.variant});

  final String label;
  final String text;
  final _CopyVariant variant;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isGood = variant == _CopyVariant.good;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: isGood ? colors.statusSuccessSurface : colors.statusDangerSurface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: isGood ? colors.statusSuccessBorder : colors.statusDangerBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.space4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isGood ? Icons.check : Icons.close,
                  size: 14,
                  color: isGood ? colors.statusSuccessFg : colors.statusDangerFg,
                ),
                const SizedBox(width: AppSpacing.space2),
                Text(label, style: DevTextStyles.overline(context)),
              ],
            ),
            const SizedBox(height: AppSpacing.space2),
            Text(text, style: AppTypography.body(context)),
          ],
        ),
      ),
    );
  }
}

class _HouseRule extends StatelessWidget {
  const _HouseRule(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.space2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('• ', style: AppTypography.body(context).copyWith(color: context.appColors.textSecondary)),
          Expanded(
            child: Text(text, style: AppTypography.body(context).copyWith(color: context.appColors.textSecondary)),
          ),
        ],
      ),
    );
  }
}
