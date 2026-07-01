import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/shadow_tokens.dart';
import 'package:ai_clinic/core/ui/theme/shape_tokens.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';

/// Which edge of [AppTooltipContent] the pointer arrow sits on.
enum AppTooltipArrowDirection { top, bottom, left, right }

/// Forui [FTooltip] style that strips default chrome so only [AppTooltipContent] shows.
abstract final class AppTooltipOverlayStyle {
  static const chromeFree = FTooltipStyleDelta.delta(
    decoration: DecorationDelta.value(BoxDecoration(color: Colors.transparent)),
    padding: EdgeInsetsDelta.value(EdgeInsets.zero),
    backgroundFilter: null,
    hoverEnterDuration: Duration.zero,
    motion: FTooltipMotionDelta.delta(entranceDuration: Duration(milliseconds: 200)),
  );
}

/// Rich tooltip panel — title, optional icon, generic description body, and directional arrow.
///
/// Use as the visible tip inside forui [FTooltip] `tipBuilder` with
/// [AppTooltipOverlayStyle.chromeFree], or inside [OverlayPortal]; this widget
/// does not attach hover or focus behavior to a target.
class AppTooltipContent extends StatelessWidget {
  const AppTooltipContent({
    required this.title,
    this.icon,
    this.description,
    this.maxWidth = 288,
    this.arrowDirection = AppTooltipArrowDirection.bottom,
    super.key,
  });

  final String title;
  final Widget? icon;
  final Widget? description;
  final double maxWidth;
  final AppTooltipArrowDirection arrowDirection;

  static const _arrowSize = 12.0;
  static const _arrowOffset = 6.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final shapes = context.shapeTokens;
    final textTheme = Theme.of(context).textTheme;
    final borderRadius = BorderRadius.circular(shapes.xl);
    final borderColor = colors.foreground.withValues(alpha: 0.1);
    final surfaceStart = colors.popover.withValues(alpha: 0.97);
    final surfaceEnd = colors.card.withValues(alpha: 0.95);

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipRRect(
            borderRadius: borderRadius,
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [surfaceStart, surfaceEnd],
                  ),
                  borderRadius: borderRadius,
                  border: Border.all(color: borderColor),
                  boxShadow: [
                    BoxShadow(color: colors.primary.withValues(alpha: 0.15), blurRadius: 30),
                    ...ShadowTokens.shadowLg,
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(SpacingTokens.md),
                  child: _body(context, colors, textTheme),
                ),
              ),
            ),
          ),
          _TooltipArrow(
            direction: arrowDirection,
            surfaceStart: surfaceStart,
            surfaceEnd: surfaceEnd,
            borderColor: borderColor,
          ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, SemanticColors colors, TextTheme textTheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _header(colors, textTheme),
        if (description != null) ...[const SizedBox(height: SpacingTokens.sm), description!],
      ],
    );
  }

  Widget _header(SemanticColors colors, TextTheme textTheme) {
    return Row(
      children: [
        if (icon != null) ...[
          DecoratedBox(
            decoration: BoxDecoration(color: colors.primary.withValues(alpha: 0.2), shape: BoxShape.circle),
            child: SizedBox(
              width: 32,
              height: 32,
              child: IconTheme.merge(
                data: IconThemeData(size: 16, color: colors.primary),
                child: Center(child: icon),
              ),
            ),
          ),
          const SizedBox(width: SpacingTokens.md - 4),
        ],
        Expanded(
          child: Text(
            title,
            style: textTheme.titleSmall?.copyWith(color: colors.popoverForeground, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _TooltipArrow extends StatelessWidget {
  const _TooltipArrow({
    required this.direction,
    required this.surfaceStart,
    required this.surfaceEnd,
    required this.borderColor,
  });

  final AppTooltipArrowDirection direction;
  final Color surfaceStart;
  final Color surfaceEnd;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    final alignment = switch (direction) {
      AppTooltipArrowDirection.top => Alignment.topCenter,
      AppTooltipArrowDirection.bottom => Alignment.bottomCenter,
      AppTooltipArrowDirection.left => Alignment.centerLeft,
      AppTooltipArrowDirection.right => Alignment.centerRight,
    };

    final offset = switch (direction) {
      AppTooltipArrowDirection.top => const Offset(0, -AppTooltipContent._arrowOffset),
      AppTooltipArrowDirection.bottom => const Offset(0, AppTooltipContent._arrowOffset),
      AppTooltipArrowDirection.left => const Offset(-AppTooltipContent._arrowOffset, 0),
      AppTooltipArrowDirection.right => const Offset(AppTooltipContent._arrowOffset, 0),
    };

    final borderSide = switch (direction) {
      AppTooltipArrowDirection.top => Border(
        top: BorderSide(color: borderColor),
        left: BorderSide(color: borderColor),
      ),
      AppTooltipArrowDirection.bottom => Border(
        right: BorderSide(color: borderColor),
        bottom: BorderSide(color: borderColor),
      ),
      AppTooltipArrowDirection.left => Border(
        top: BorderSide(color: borderColor),
        left: BorderSide(color: borderColor),
      ),
      AppTooltipArrowDirection.right => Border(
        right: BorderSide(color: borderColor),
        bottom: BorderSide(color: borderColor),
      ),
    };

    return Positioned.fill(
      child: Align(
        alignment: alignment,
        child: Transform.translate(
          offset: offset,
          child: Transform.rotate(
            angle: 0.785398, // π/4
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [surfaceStart, surfaceEnd],
                ),
                border: borderSide,
              ),
              child: const SizedBox(width: AppTooltipContent._arrowSize, height: AppTooltipContent._arrowSize),
            ),
          ),
        ),
      ),
    );
  }
}
