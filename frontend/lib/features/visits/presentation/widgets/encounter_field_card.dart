import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/shape_tokens.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_page_tokens.dart';

/// Gradient card shell for encounter phase fields (Complaint, History, Examination, Diagnosis).
class EncounterFieldCard extends StatelessWidget {
  const EncounterFieldCard({
    required this.title,
    required this.titleIcon,
    required this.child,
    this.expandBody = false,
    this.embedTitleInToolbar = false,
    this.headerTrailing,
    super.key,
  });

  final String title;
  final IconData titleIcon;
  final Widget child;
  final bool expandBody;
  final bool embedTitleInToolbar;
  final Widget? headerTrailing;

  @override
  Widget build(BuildContext context) {
    final theme = context.visitTheme;
    final colors = context.semanticColors;
    final borderRadius = BorderRadius.circular(context.shapeTokens.lg);

    final bodyPadding = embedTitleInToolbar
        ? const EdgeInsets.all(SpacingTokens.md)
        : const EdgeInsets.fromLTRB(SpacingTokens.md, 0, SpacingTokens.md, SpacingTokens.md);

    final body = Padding(padding: bodyPadding, child: child);

    final card = DecoratedBox(
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: borderRadius,
        border: Border.all(color: colors.border),
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: Stack(
          fit: expandBody ? StackFit.expand : StackFit.loose,
          children: [
            Positioned.fill(
              child: DecoratedBox(decoration: BoxDecoration(gradient: theme.pulseCardGradient)),
            ),
            TiltedBackgroundIconStack(
              icon: titleIcon,
              iconSize: VisitPageTokens.subjectiveWatermarkIconSize,
              iconColor: theme.subjectiveWatermark,
              fillChild: expandBody,
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: double.infinity,
                height: expandBody ? double.infinity : null,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: expandBody ? MainAxisSize.max : MainAxisSize.min,
                  children: [
                    if (!embedTitleInToolbar)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          SpacingTokens.md,
                          SpacingTokens.md,
                          SpacingTokens.md,
                          SpacingTokens.md,
                        ),
                        child: Row(
                          children: [
                            Icon(titleIcon, size: 20, color: theme.pulse),
                            const SizedBox(width: SpacingTokens.sm),
                            Expanded(child: Text(title, style: theme.title())),
                            if (headerTrailing != null) ...[const SizedBox(width: SpacingTokens.xs), headerTrailing!],
                          ],
                        ),
                      ),
                    if (expandBody) Expanded(child: body) else body,
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (expandBody) {
      return SizedBox(width: double.infinity, height: double.infinity, child: card);
    }

    return card;
  }
}

/// Title row pinned to the left of a rich-text toolbar.
class EncounterToolbarTitle extends StatelessWidget {
  const EncounterToolbarTitle({required this.title, required this.icon, super.key});

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = context.visitTheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: SpacingTokens.sm,
      children: [
        Icon(icon, size: 20, color: theme.pulse),
        Text(title, style: theme.title()),
      ],
    );
  }
}

/// Read-only text for encounter field cards in detail view.
class EncounterDetailText extends StatelessWidget {
  const EncounterDetailText({required this.value, super.key});

  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = context.visitTheme;
    final display = value.trim().isEmpty ? '—' : value.trim();
    final isEmpty = value.trim().isEmpty;

    return Text(display, style: theme.body(color: isEmpty ? theme.mutedInk : theme.ink));
  }
}
