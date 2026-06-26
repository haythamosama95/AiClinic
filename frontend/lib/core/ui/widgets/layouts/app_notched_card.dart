import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import 'package:ai_clinic/core/ui/theme/theme.dart';
import 'package:ai_clinic/core/ui/widgets/layouts/notched_card_path.dart';

/// Dashboard panel with a top-trailing step-down cut-out for floating actions.
///
/// Mirrors [AppCard] chrome on three corners; actions render in the notch shelf
/// when supplied (see phase-4 wiring). Only the title reserves trailing space
/// so it does not overlap the cut-out.
class AppNotchedCard extends StatelessWidget {
  const AppNotchedCard({required this.body, this.title, this.description, this.actions, super.key});

  final Widget body;
  final Widget? title;
  final Widget? description;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final borderRadius = context.shapeTokens.lg;
    final contentStyle = context.theme.cardStyle.contentStyle;
    final textDirection = Directionality.of(context);

    // US1: static minimum notch; action-driven width lands in a later phase.
    final notchWidth = kNotchMinWidth;
    final trailingInset = notchWidth;

    return LayoutBuilder(
      builder: (context, constraints) {
        return CustomPaint(
          foregroundPainter: NotchedCardBorderPainter(
            borderColor: colors.border,
            borderRadius: borderRadius,
            notchWidth: notchWidth,
            textDirection: textDirection,
          ),
          child: ClipPath(
            clipper: NotchedCardClipper(
              borderRadius: borderRadius,
              notchWidth: notchWidth,
              textDirection: textDirection,
            ),
            child: ColoredBox(
              color: colors.card,
              child: Padding(
                padding: contentStyle.padding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (title != null)
                      Padding(
                        padding: EdgeInsetsDirectional.only(end: trailingInset),
                        child: DefaultTextStyle.merge(
                          textHeightBehavior: const TextHeightBehavior(
                            applyHeightToFirstAscent: false,
                            applyHeightToLastDescent: false,
                          ),
                          style: contentStyle.titleTextStyle,
                          child: title!,
                        ),
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
                    if (title != null && description != null) SizedBox(height: contentStyle.subtitleSpacing),
                    body,
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
