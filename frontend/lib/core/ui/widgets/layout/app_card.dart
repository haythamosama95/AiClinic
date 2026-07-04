import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/foundation.dart';

/// Visual treatment for [AppCard].
enum AppCardVariant {
  /// Default surface with a default border and no elevation.
  flat,

  /// Raised surface with subtle border and elevation-1 shadow.
  raised,

  /// Hover tint and focus ring; whole card is pressable when [onTap] is set.
  interactive,

  /// AI-accented surface and border.
  ai,
}

/// Internal padding scale for [AppCard] body content.
enum AppCardPadding {
  /// 16 logical pixels (`space-4`).
  sm,

  /// 20 logical pixels (`space-5`, default).
  md,

  /// 24 logical pixels (`space-6`).
  lg,
}

/// Grouped surface with optional header, body, and footer slots.
class AppCard extends StatelessWidget {
  /// Creates a card with optional [title], [headerActions], [header], [footer],
  /// and [child] body content.
  const AppCard({
    this.variant = AppCardVariant.flat,
    this.padding = AppCardPadding.md,
    this.title,
    this.headerActions,
    this.header,
    this.footer,
    this.onTap,
    this.semanticLabel,
    this.child,
    super.key,
  });

  final AppCardVariant variant;
  final AppCardPadding padding;
  final String? title;
  final Widget? headerActions;
  final Widget? header;
  final Widget? footer;
  final VoidCallback? onTap;
  final String? semanticLabel;
  final Widget? child;

  static double _paddingValue(AppCardPadding padding) => switch (padding) {
    AppCardPadding.sm => AppSpacing.s4,
    AppCardPadding.md => AppSpacing.s5,
    AppCardPadding.lg => AppSpacing.s6,
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final brightness = Theme.of(context).brightness;
    final borderRadius = AppRadii.lgAll;
    final hasHeader = header != null || title != null;
    final hasFooter = footer != null;
    final bodyPadding = _paddingValue(padding);
    final isPressable = onTap != null;

    Widget cardContent(BuildContext context, Set<WidgetState> states) {
      final decoration = _decoration(
        colors: colors,
        brightness: brightness,
        variant: variant,
        states: states,
        isPressable: isPressable,
      );

      return AnimatedContainer(
        duration: AppDurations.instant,
        curve: AppEasings.standard,
        decoration: decoration,
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (hasHeader)
              _CardHeader(
                title: title,
                headerActions: headerActions,
                header: header,
              ),
            if (child != null)
              Padding(
                padding: EdgeInsetsDirectional.all(
                  hasHeader || hasFooter ? AppSpacing.s5 : bodyPadding,
                ),
                child: child,
              ),
            if (hasFooter)
              DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: colors.borderSubtle),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsetsDirectional.symmetric(
                    horizontal: AppSpacing.s5,
                    vertical: AppSpacing.s4,
                  ),
                  child: footer!,
                ),
              ),
          ],
        ),
      );
    }

    Widget card = isPressable
        ? AppPressable.builder(
            onTap: onTap,
            semanticLabel: semanticLabel,
            borderRadius: borderRadius,
            builder: (context, states, _) => cardContent(context, states),
          )
        : cardContent(context, const {});

    if (semanticLabel != null) {
      card = Semantics(
        container: true,
        label: semanticLabel,
        child: card,
      );
    }

    return card;
  }

  static BoxDecoration _decoration({
    required AppColors colors,
    required Brightness brightness,
    required AppCardVariant variant,
    required Set<WidgetState> states,
    required bool isPressable,
  }) {
    final hovered = states.contains(WidgetState.hovered);
    final focused = states.contains(WidgetState.focused);

    final (background, borderColor, elevation) = switch (variant) {
      AppCardVariant.flat => (
        colors.surfaceDefault,
        colors.borderDefault,
        0,
      ),
      AppCardVariant.raised => (
        colors.surfaceRaised,
        colors.borderSubtle,
        1,
      ),
      AppCardVariant.interactive => (
        hovered && isPressable ? colors.surfaceHover : colors.surfaceDefault,
        focused && isPressable ? colors.borderFocus : colors.borderDefault,
        0,
      ),
      AppCardVariant.ai => (
        colors.surfaceAi,
        colors.borderAi,
        0,
      ),
    };

    return BoxDecoration(
      color: background,
      border: Border.all(color: borderColor),
      borderRadius: AppRadii.lgAll,
      boxShadow: AppShadows.forLevel(elevation, brightness),
    );
  }
}

class _CardHeader extends StatelessWidget {
  const _CardHeader({
    this.title,
    this.headerActions,
    this.header,
  });

  final String? title;
  final Widget? headerActions;
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    final content = header ??
        Row(
          children: [
            if (title != null)
              Expanded(
                child: Text(
                  title!,
                  style: typography.bodyStrong.copyWith(
                    color: colors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ?headerActions,
          ],
        );

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: colors.borderSubtle),
        ),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: AppSpacing.s5,
          vertical: AppSpacing.s4,
        ),
        child: content,
      ),
    );
  }
}
