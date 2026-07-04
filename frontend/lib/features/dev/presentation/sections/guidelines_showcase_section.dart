import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/foundation.dart';
import 'package:ai_clinic/core/ui/patterns/pattern_scaffold.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/dev/presentation/widgets/showcase_section.dart';

/// Guidelines tab — accessibility and voice principles.
class GuidelinesShowcaseSection extends StatelessWidget {
  const GuidelinesShowcaseSection({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Milestone 6',
          style: typography.overline.copyWith(color: colors.textTertiary),
        ),
        const SizedBox(height: AppSpacing.s1),
        Text(
          'Guidelines',
          style: typography.h2.copyWith(color: colors.textPrimary),
        ),
        const SizedBox(height: AppSpacing.s2),
        Text(
          'Accessibility targets and product voice for Calm Clinical Precision.',
          style: typography.bodyLg.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: PatternScaffold.sectionGap),
        ShowcaseSection(
          id: 'guidelines-accessibility',
          title: 'Accessibility',
          description: 'Semantic token pairs verified for WCAG 2.2 AA in light and dark themes.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const AppAlert(
                variant: AppAlertVariant.info,
                title: 'Contrast-first surfaces',
                body:
                    'Primary copy, actions, and status treatments are validated against their surface backgrounds in both themes.',
              ),
              const SizedBox(height: AppSpacing.s4),
              _GuidelineCard(
                title: 'Focus visibility',
                body: 'Interactive controls use AppPressable with visible focus rings — standard teal or AI violet when AI mode is active.',
              ),
              const SizedBox(height: AppSpacing.s3),
              _GuidelineCard(
                title: 'Motion respect',
                body: 'Honor system reduced-motion settings and the showcase override. Presets collapse to instant transitions when motion is reduced.',
              ),
              const SizedBox(height: AppSpacing.s3),
              _GuidelineCard(
                title: 'RTL & Arabic',
                body: 'Directionality follows locale. Arabic uses IBM Plex Sans Arabic with adjusted line heights in the typography scale.',
              ),
            ],
          ),
        ),
        const SizedBox(height: PatternScaffold.sectionGap),
        ShowcaseSection(
          id: 'guidelines-voice',
          title: 'Voice & tone',
          description: 'Operational clarity with calm, precise language.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _GuidelineCard(
                title: 'Be specific',
                body: 'Prefer "Register patient" over generic "Submit". Name the object and the outcome.',
              ),
              const SizedBox(height: AppSpacing.s3),
              _GuidelineCard(
                title: 'Surface risk early',
                body: 'Destructive and financial confirmations lead with the consequence, then offer a safe cancel path.',
              ),
              const SizedBox(height: AppSpacing.s3),
              _GuidelineCard(
                title: 'AI is assistive',
                body: 'AI suggestions are proposals — always show review, edit, and dismiss affordances before applying changes.',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _GuidelineCard extends StatelessWidget {
  const _GuidelineCard({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: AppRadii.lgAll,
        border: Border.all(color: colors.borderDefault),
        color: colors.surfaceDefault,
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.all(AppSpacing.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: typography.bodyStrong.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(height: AppSpacing.s1),
            Text(
              body,
              style: typography.body.copyWith(color: colors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
