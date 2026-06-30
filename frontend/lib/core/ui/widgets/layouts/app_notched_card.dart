import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import 'package:ai_clinic/core/ui/theme/theme.dart';
import 'package:ai_clinic/core/ui/widgets/buttons/app_button.dart';
import 'package:ai_clinic/core/ui/widgets/buttons/app_icon_button.dart';
import 'package:ai_clinic/core/ui/widgets/input/app_field_size.dart';
import 'package:ai_clinic/core/ui/widgets/layouts/notched_card_path.dart';

/// Optional wrapper for an [AppNotchedCard] shelf action.
///
/// When [providesOwnBackground] is true the card renders [action] as-is (for
/// example a filled [AppButton]). When false (default) the card applies its
/// standard card-colored stadium shell around [action].
class AppNotchedCardAction extends StatelessWidget {
  const AppNotchedCardAction({required this.action, this.providesOwnBackground = false, super.key});

  final Widget action;
  final bool providesOwnBackground;

  @override
  Widget build(BuildContext context) => action;
}

/// Dashboard panel with a top-trailing step-down cut-out for floating actions.
///
/// Mirrors [AppCard] chrome on three corners; caller-supplied [actions] float
/// centered in the notch shelf. Only the title reserves trailing space so it
/// does not overlap the cut-out.
class AppNotchedCard extends StatelessWidget {
  const AppNotchedCard({required this.body, this.title, this.titleIcon, this.description, this.actions, super.key});

  final Widget body;
  final Widget? title;
  final IconData? titleIcon;
  final Widget? description;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return _AppNotchedCardLayout(
          constraints: constraints,
          body: body,
          title: title,
          titleIcon: titleIcon,
          description: description,
          actions: actions,
        );
      },
    );
  }
}

/// Computes notch shelf width from measured action row width and card bounds.
double computeNotchWidth({
  required double cardWidth,
  required double borderRadius,
  double? actionsRowWidth,
  double shelfDepth = kNotchShelfDepth,
}) {
  final fillet = kNotchFilletRadius.clamp(0.0, shelfDepth / 2).toDouble();
  final maxNotchWidth = (cardWidth - borderRadius - fillet * 2).clamp(0.0, double.infinity).toDouble();

  final desiredWidth = actionsRowWidth == null ? kNotchMinWidth : actionsRowWidth + 2 * kNotchHorizontalPadding;

  if (maxNotchWidth < kNotchMinWidth) {
    return desiredWidth.clamp(0.0, maxNotchWidth).toDouble();
  }

  return desiredWidth.clamp(kNotchMinWidth, maxNotchWidth).toDouble();
}

/// Computes notch shelf depth from measured action row height.
double computeShelfDepth({double? actionsRowHeight}) {
  if (actionsRowHeight == null) {
    return kNotchShelfDepth;
  }

  // Ceil so fractional layout sizes never clip the action chrome by a sub-pixel.
  return actionsRowHeight.clamp(kNotchShelfDepth, double.infinity).ceilToDouble();
}

class _AppNotchedCardLayout extends StatefulWidget {
  const _AppNotchedCardLayout({
    required this.constraints,
    required this.body,
    this.title,
    this.titleIcon,
    this.description,
    this.actions,
  });

  final BoxConstraints constraints;
  final Widget body;
  final Widget? title;
  final IconData? titleIcon;
  final Widget? description;
  final List<Widget>? actions;

  @override
  State<_AppNotchedCardLayout> createState() => _AppNotchedCardLayoutState();
}

class _AppNotchedCardLayoutState extends State<_AppNotchedCardLayout> {
  final GlobalKey _actionsMeasureKey = GlobalKey();
  double? _actionsRowWidth;
  double? _actionsRowHeight;

  bool get _hasActions => widget.actions != null && widget.actions!.isNotEmpty;

  @override
  void didUpdateWidget(covariant _AppNotchedCardLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_listEquals(oldWidget.actions, widget.actions)) {
      _actionsRowWidth = null;
      _actionsRowHeight = null;
    }
  }

  void _scheduleActionsMeasure() {
    if (!_hasActions) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      final renderBox = _actionsMeasureKey.currentContext?.findRenderObject() as RenderBox?;
      final size = renderBox?.hasSize == true ? renderBox!.size : null;
      if (size != null && (size.width != _actionsRowWidth || size.height != _actionsRowHeight)) {
        setState(() {
          _actionsRowWidth = size.width;
          _actionsRowHeight = size.height;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    _scheduleActionsMeasure();

    final colors = context.semanticColors;
    final borderRadius = context.shapeTokens.lg;
    final contentStyle = context.theme.cardStyle.contentStyle;
    final textDirection = Directionality.of(context);
    final cardWidth = widget.constraints.maxWidth;

    final shelfDepth = computeShelfDepth(actionsRowHeight: _hasActions ? _actionsRowHeight : null);

    final notchWidth = computeNotchWidth(
      cardWidth: cardWidth,
      borderRadius: borderRadius,
      actionsRowWidth: _hasActions ? _actionsRowWidth : null,
      shelfDepth: shelfDepth,
    );
    final trailingInset = notchWidth;

    final shelf = NotchedCardPath.shelfRect(
      size: Size(cardWidth, widget.constraints.maxHeight),
      borderRadius: borderRadius,
      notchWidth: notchWidth,
      shelfDepth: shelfDepth,
      textDirection: textDirection,
    );

    final expandsVertically = widget.constraints.maxHeight.isFinite;

    return Stack(
      clipBehavior: Clip.none,
      fit: StackFit.passthrough,
      children: [
        CustomPaint(
          foregroundPainter: NotchedCardBorderPainter(
            borderColor: colors.border,
            borderRadius: borderRadius,
            notchWidth: notchWidth,
            shelfDepth: shelfDepth,
            textDirection: textDirection,
          ),
          child: ClipPath(
            clipper: NotchedCardClipper(
              borderRadius: borderRadius,
              notchWidth: notchWidth,
              shelfDepth: shelfDepth,
              textDirection: textDirection,
            ),
            child: ColoredBox(
              color: colors.card,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: expandsVertically ? MainAxisSize.max : MainAxisSize.min,
                children: [
                  if (widget.title != null || widget.description != null)
                    Padding(
                      padding: contentStyle.padding,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.title != null)
                            Padding(
                              padding: EdgeInsetsDirectional.only(end: trailingInset),
                              child: _NotchedCardTitleRow(title: widget.title!, titleIcon: widget.titleIcon),
                            ),
                          if (widget.title != null && widget.description != null)
                            SizedBox(height: contentStyle.titleSpacing),
                          if (widget.description != null)
                            DefaultTextStyle.merge(
                              textHeightBehavior: const TextHeightBehavior(
                                applyHeightToFirstAscent: false,
                                applyHeightToLastDescent: false,
                              ),
                              style: contentStyle.subtitleTextStyle,
                              child: widget.description!,
                            ),
                        ],
                      ),
                    ),
                  if (expandsVertically) Expanded(child: widget.body) else widget.body,
                ],
              ),
            ),
          ),
        ),
        if (_hasActions)
          Positioned.fill(
            child: ClipRect(
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  PositionedDirectional(
                    start: _actionsRowWidth == null
                        ? -10000
                        : _shelfActionStart(
                            shelf: shelf,
                            cardWidth: cardWidth,
                            actionsRowWidth: _actionsRowWidth!,
                            textDirection: textDirection,
                          ),
                    top: shelf.top,
                    child: _buildActionsRow(
                      key: _actionsMeasureKey,
                      backgroundColor: colors.card,
                      borderColor: colors.border,
                      actions: widget.actions!,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _NotchedCardTitleRow extends StatelessWidget {
  const _NotchedCardTitleRow({required this.title, this.titleIcon});

  final Widget title;
  final IconData? titleIcon;

  @override
  Widget build(BuildContext context) {
    final contentStyle = context.theme.cardStyle.contentStyle;

    final titleText = DefaultTextStyle.merge(
      textHeightBehavior: const TextHeightBehavior(applyHeightToFirstAscent: false, applyHeightToLastDescent: false),
      style: contentStyle.titleTextStyle,
      child: title,
    );

    if (titleIcon == null) {
      return titleText;
    }

    final colors = context.semanticColors;

    return Row(
      spacing: SpacingTokens.sm,
      children: [
        Icon(titleIcon, size: 20, color: colors.primary),
        Expanded(child: titleText),
      ],
    );
  }
}

Widget _buildActionsRow({
  required Color backgroundColor,
  required Color borderColor,
  required List<Widget> actions,
  Key? key,
}) {
  return Padding(
    key: key,
    padding: const EdgeInsets.fromLTRB(
      kNotchActionMargin,
      kNotchActionMargin,
      kNotchActionMargin,
      kNotchActionBottomMargin,
    ),
    child: _NotchedCardActionsRow(backgroundColor: backgroundColor, borderColor: borderColor, actions: actions),
  );
}

/// Card-colored row of per-action shells in the notch shelf.
class _NotchedCardActionsRow extends StatelessWidget {
  const _NotchedCardActionsRow({required this.backgroundColor, required this.borderColor, required this.actions});

  final Color backgroundColor;
  final Color borderColor;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: SpacingTokens.sm,
        children: [
          for (final action in actions)
            _NotchedCardActionShell(
              backgroundColor: backgroundColor,
              borderColor: borderColor,
              parsed: _parseNotchedCardAction(action),
            ),
        ],
      ),
    );
  }
}

/// Card-colored stadium shell for a single caller action.
///
/// Hover and press are handled on the shell [InkWell] so feedback covers the
/// full stadium (including padding). Caller actions are display-only here to
/// avoid nested pointer/hover regions on [IconButton] and forui controls.
class _NotchedCardActionShell extends StatelessWidget {
  const _NotchedCardActionShell({required this.backgroundColor, required this.borderColor, required this.parsed});

  final Color backgroundColor;
  final Color borderColor;
  final ({Widget action, bool providesOwnBackground}) parsed;

  @override
  Widget build(BuildContext context) {
    final action = parsed.action;

    if (parsed.providesOwnBackground) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: SpacingTokens.xs),
        child: Center(child: action),
      );
    }

    final onPressed = _actionOnPressed(action);
    if (onPressed == null && action is! AppIconButton && action is! AppButton) {
      return DecoratedBox(
        decoration: ShapeDecoration(
          color: backgroundColor,
          shape: StadiumBorder(side: BorderSide(color: borderColor)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(kNotchActionContainerPadding),
          child: Center(child: action),
        ),
      );
    }

    final colors = context.semanticColors;
    final tooltip = switch (action) {
      AppIconButton(:final tooltip) => tooltip,
      _ => null,
    };

    final shell = Material(
      color: backgroundColor,
      shape: StadiumBorder(side: BorderSide(color: borderColor)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        customBorder: const StadiumBorder(),
        overlayColor: WidgetStateProperty.resolveWith((states) {
          if (!states.contains(WidgetState.hovered) && !states.contains(WidgetState.pressed)) {
            return null;
          }

          return colors.foreground.withValues(alpha: 0.08);
        }),
        child: Padding(
          padding: const EdgeInsets.all(kNotchActionContainerPadding),
          child: Center(child: _NotchedCardActionDisplay(action: action)),
        ),
      ),
    );

    if (tooltip == null) {
      return shell;
    }

    return Tooltip(message: tooltip, child: shell);
  }
}

/// Visual-only rendering of supported caller actions inside the notch shell.
class _NotchedCardActionDisplay extends StatelessWidget {
  const _NotchedCardActionDisplay({required this.action});

  final Widget action;

  @override
  Widget build(BuildContext context) {
    if (action is AppIconButton) {
      final button = action as AppIconButton;
      final colors = context.semanticColors;
      final foreground = switch (button.variant) {
        AppIconButtonVariant.ghost => colors.foreground,
        AppIconButtonVariant.outline => colors.foreground,
        AppIconButtonVariant.muted => colors.mutedForeground,
      };

      return SizedBox(
        width: button.size,
        height: button.size,
        child: IconTheme.merge(
          data: IconThemeData(color: foreground),
          child: button.icon,
        ),
      );
    }

    if (action is AppButton) {
      return _NotchedCardButtonDisplay(button: action as AppButton);
    }

    return IgnorePointer(child: action);
  }
}

class _NotchedCardButtonDisplay extends StatelessWidget {
  const _NotchedCardButtonDisplay({required this.button});

  final AppButton button;

  @override
  Widget build(BuildContext context) {
    final style = _resolveAppButtonStyle(context, button);
    final contentStyle = style.contentStyle;
    final variants = button.onPressed == null ? {FTappableVariant.disabled} : const <FTappableVariant>{};
    final textStyle = contentStyle.textStyle.resolve(variants);
    final iconStyle = contentStyle.iconStyle.resolve(variants);

    return ConstrainedBox(
      constraints: contentStyle.constraints,
      child: Padding(
        padding: contentStyle.padding,
        child: DefaultTextStyle.merge(
          style: textStyle,
          child: IconTheme(
            data: iconStyle,
            child: button.isLoading
                ? FCircularProgress(size: button.size.progressSize)
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: contentStyle.spacing,
                    children: [
                      if (button.icon != null) button.icon!,
                      Text(button.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

FButtonStyle _resolveAppButtonStyle(BuildContext context, AppButton button) {
  return const FButtonStyleDelta.context()(
    context.theme.buttonStyles.resolve({_mapFButtonVariant(button.variant), context.platformVariant}).resolve({
      button.size.buttonSize,
      context.platformVariant,
    }),
  );
}

FButtonVariant _mapFButtonVariant(AppButtonVariant variant) => switch (variant) {
  AppButtonVariant.primary => FButtonVariant.primary,
  AppButtonVariant.secondary => FButtonVariant.secondary,
  AppButtonVariant.destructive => FButtonVariant.destructive,
  AppButtonVariant.outline => FButtonVariant.outline,
  AppButtonVariant.ghost => FButtonVariant.ghost,
};

({Widget action, bool providesOwnBackground}) _parseNotchedCardAction(Widget widget) {
  if (widget is AppNotchedCardAction) {
    return (action: widget.action, providesOwnBackground: widget.providesOwnBackground);
  }

  return (action: widget, providesOwnBackground: false);
}

VoidCallback? _actionOnPressed(Widget action) {
  if (action is AppButton && action.isLoading) {
    return null;
  }

  return switch (action) {
    AppIconButton(:final onPressed) => onPressed,
    AppButton(:final onPressed) => onPressed,
    _ => null,
  };
}

/// Horizontal [PositionedDirectional.start] offset to center actions in the shelf.
double _shelfActionStart({
  required Rect shelf,
  required double cardWidth,
  required double actionsRowWidth,
  required TextDirection textDirection,
}) {
  final centerX = shelf.left + shelf.width / 2;

  return switch (textDirection) {
    TextDirection.ltr => centerX - actionsRowWidth / 2,
    TextDirection.rtl => cardWidth - centerX - actionsRowWidth / 2,
  };
}

bool _listEquals(List<Widget>? a, List<Widget>? b) {
  if (identical(a, b)) {
    return true;
  }
  if (a == null || b == null || a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i].key != b[i].key || a[i].runtimeType != b[i].runtimeType) {
      return false;
    }
  }
  return true;
}
