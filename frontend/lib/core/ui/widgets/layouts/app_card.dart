import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import 'package:ai_clinic/core/ui/theme/theme.dart';

/// Dashboard panel container wrapping [FCard] with optional header actions.
class AppCard extends StatelessWidget {
  const AppCard({required this.child, this.title, this.description, this.actions, this.expand = false, super.key});

  final Widget? title;
  final Widget? description;
  final Widget child;
  final List<Widget>? actions;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final cardStyle = FCardStyleDelta.delta(
      decoration: DecorationDelta.boxDelta(
        color: colors.card,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(context.shapeTokens.lg),
      ),
    );

    if (!expand) {
      return FCard(
        title: title,
        subtitle: description,
        style: cardStyle,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            child,
            if (actions != null && actions!.isNotEmpty) ...[
              const SizedBox(height: SpacingTokens.md),
              Row(mainAxisAlignment: MainAxisAlignment.end, spacing: SpacingTokens.sm, children: actions!),
            ],
          ],
        ),
      );
    }

    // FCard's content column gives its child unbounded height, so Expanded cannot
    // live inside a nested column passed as FCard.child. Build the expandable
    // layout directly under FCard.raw instead.
    final contentStyle = context.theme.cardStyle.contentStyle;
    final hasHeader = title != null || description != null;

    return FCard.raw(
      style: cardStyle,
      child: Padding(
        padding: contentStyle.padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.max,
          children: [
            if (hasHeader) ...[
              if (title != null)
                DefaultTextStyle.merge(
                  textHeightBehavior: const TextHeightBehavior(
                    applyHeightToFirstAscent: false,
                    applyHeightToLastDescent: false,
                  ),
                  style: contentStyle.titleTextStyle,
                  child: title!,
                ),
              if (title != null && description != null) SizedBox(height: contentStyle.titleSpacing),
              if (description != null)
                DefaultTextStyle.merge(
                  textHeightBehavior: const TextHeightBehavior(
                    applyHeightToFirstAscent: false,
                    applyHeightToLastDescent: false,
                  ),
                  style: contentStyle.subtitleTextStyle,
                  child: description!,
                ),
              if (description != null || title != null) SizedBox(height: contentStyle.subtitleSpacing),
            ],
            Expanded(child: child),
            if (actions != null && actions!.isNotEmpty) ...[
              const SizedBox(height: SpacingTokens.md),
              Row(mainAxisAlignment: MainAxisAlignment.end, spacing: SpacingTokens.sm, children: actions!),
            ],
          ],
        ),
      ),
    );
  }
}
