import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/components/app_signal.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

import 'foundation_section.dart';

/// The Signal foundation section with standard and AI demos.
class SignalSection extends StatefulWidget {
  const SignalSection({super.key});

  @override
  State<SignalSection> createState() => _SignalSectionState();
}

class _SignalSectionState extends State<SignalSection> {
  bool _aiThinking = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return FoundationSection(
      id: 'signal',
      title: 'The Signal',
      description: 'Signature primitive — active nav, Command Bar focus, AI thinking pulse.',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isLarge = constraints.maxWidth >= 1024;

          final standardCard = _SignalCard(
            borderColor: colors.borderDefault,
            backgroundColor: colors.surfaceDefault,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Standard (teal)', style: AppTypography.overline(context)),
                const SizedBox(height: AppSpacing.space4),
                SizedBox(
                  height: 56,
                  child: Stack(
                    children: [
                      PositionedDirectional(
                        start: 0,
                        top: 8,
                        bottom: 8,
                        child: const AppSignal(orientation: Axis.vertical),
                      ),
                      Padding(
                        padding: const EdgeInsetsDirectional.only(start: AppSpacing.space4 + 2),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Active navigation item', style: AppTypography.bodyStrong(context)),
                            const SizedBox(height: AppSpacing.space1),
                            Text('Patients', style: AppTypography.caption(context)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.space6),
                Text('Horizontal · hero', style: AppTypography.caption(context)),
                const SizedBox(height: AppSpacing.space2),
                const SizedBox(
                  width: 320,
                  child: AppSignal(orientation: Axis.horizontal, size: AppSignalSize.hero),
                ),
              ],
            ),
          );

          final aiCard = _SignalCard(
            borderColor: colors.borderAi,
            backgroundColor: colors.surfaceAi,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('AI (violet)', style: AppTypography.overline(context).copyWith(color: colors.textAi)),
                const SizedBox(height: AppSpacing.space4),
                SizedBox(
                  width: double.infinity,
                  child: AppSignal(variant: AppSignalVariant.ai, orientation: Axis.horizontal, thinking: _aiThinking),
                ),
                const SizedBox(height: AppSpacing.space4),
                Text(
                  'AI is drafting a proposed action…',
                  style: AppTypography.body(context).copyWith(color: colors.textAi),
                ),
                const SizedBox(height: AppSpacing.space4),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.actionAi,
                    foregroundColor: colors.actionAiFg,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space4, vertical: AppSpacing.space2),
                  ),
                  onPressed: () => setState(() => _aiThinking = !_aiThinking),
                  child: Text(
                    _aiThinking ? 'Stop pulse' : 'Start thinking pulse',
                    style: AppTypography.bodyStrong(context).copyWith(color: colors.actionAiFg),
                  ),
                ),
              ],
            ),
          );

          if (isLarge) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: standardCard),
                const SizedBox(width: AppSpacing.space8),
                Expanded(child: aiCard),
              ],
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              standardCard,
              const SizedBox(height: AppSpacing.space8),
              aiCard,
            ],
          );
        },
      ),
    );
  }
}

class _SignalCard extends StatelessWidget {
  const _SignalCard({required this.borderColor, required this.backgroundColor, required this.child});

  final Color borderColor;
  final Color backgroundColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: borderColor),
      ),
      child: Padding(padding: const EdgeInsets.all(AppSpacing.space6), child: child),
    );
  }
}
