import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import 'package:ai_clinic/core/ui/theme/theme.dart';
import 'package:ai_clinic/core/ui/widgets/buttons/app_button.dart';
import 'package:ai_clinic/core/ui/widgets/buttons/app_icon_button.dart';
import 'package:ai_clinic/core/ui/widgets/input/app_field_size.dart';
import 'package:ai_clinic/core/ui/widgets/layouts/notched_card_path.dart';

/// Dashboard panel with a top-trailing step-down cut-out for floating actions.
///
/// Mirrors [AppCard] chrome on three corners; caller-supplied [actions] float
/// centered in the notch shelf. Only the title reserves trailing space so it
/// does not overlap the cut-out.
class AppNotchedCard extends StatelessWidget {
  const AppNotchedCard({required this.body, this.title, this.description, this.actions, super.key});

  final Widget body;
  final Widget? title;
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
  final fillet = kNotchFilletRadius.clamp(0.0, shelfDepth / 2);
  final maxNotchWidth = (cardWidth - borderRadius - fillet * 2).clamp(0.0, double.infinity);

  final desiredWidth = actionsRowWidth == null ? kNotchMinWidth : actionsRowWidth + 2 * kNotchHorizontalPadding;

  if (maxNotchWidth < kNotchMinWidth) {
    return desiredWidth.clamp(0.0, maxNotchWidth);
  }

  return desiredWidth.clamp(kNotchMinWidth, maxNotchWidth);
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
    this.description,
    this.actions,
  });

  final BoxConstraints constraints;
  final Widget body;
  final Widget? title;
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
              child: Padding(
                padding: contentStyle.padding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.title != null)
                      Padding(
                        padding: EdgeInsetsDirectional.only(end: trailingInset),
                        child: DefaultTextStyle.merge(
                          textHeightBehavior: const TextHeightBehavior(
                            applyHeightToFirstAscent: false,
                            applyHeightToLastDescent: false,
                          ),
                          style: contentStyle.titleTextStyle,
                          child: widget.title!,
                        ),
                      ),
                    if (widget.title != null && widget.description != null) SizedBox(height: contentStyle.titleSpacing),
                    if (widget.description != null)
                      DefaultTextStyle.merge(
                        textHeightBehavior: const TextHeightBehavior(
                          applyHeightToFirstAscent: false,
                          applyHeightToLastDescent: false,
                        ),
                        style: contentStyle.subtitleTextStyle,
                        child: widget.description!,
                      ),
                    if (widget.title != null && widget.description != null)
                      SizedBox(height: contentStyle.subtitleSpacing),
                    if (_hasActions) SizedBox(height: kNotchActionBottomMargin),
                    widget.body,
                  ],
                ),
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

Widget _buildActionsRow({
  required Color backgroundColor,
  required Color borderColor,
  required List<Widget> actions,
  Key? key,
}) {
  return Padding(
    key: key,
    padding: const EdgeInsets.only(bottom: kNotchActionBottomMargin),
    child: _NotchedCardActionsRow(backgroundColor: backgroundColor, borderColor: borderColor, actions: actions),
  );
}

/// Card-colored row of per-action shells in the notch shelf.
class _NotchedCardActionsRow extends StatelessWidget {
  const _NotchedCardActionsRow({
    required this.backgroundColor,
    required this.borderColor,
    required this.actions,
  });

  final Color backgroundColor;
  final Color borderColor;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: SpacingTokens.sm,
      children: [
        for (final action in actions)
          _NotchedCardActionShell(backgroundColor: backgroundColor, borderColor: borderColor, child: action),
      ],
    );
  }
}

/// Card-colored stadium shell for a single caller action.
///
/// Hover and press are handled on the shell [InkWell] so feedback covers the
/// full stadium (including padding). Caller actions are display-only here to
/// avoid nested pointer/hover regions on [IconButton] and forui controls.
class _NotchedCardActionShell extends StatelessWidget {
  const _NotchedCardActionShell({required this.backgroundColor, required this.borderColor, required this.child});

  final Color backgroundColor;
  final Color borderColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final onPressed = _actionOnPressed(child);
    if (onPressed == null && child is! AppIconButton && child is! AppButton) {
      return DecoratedBox(
        decoration: ShapeDecoration(
          color: backgroundColor,
          shape: StadiumBorder(side: BorderSide(color: borderColor)),
        ),
        child: Padding(padding: const EdgeInsets.all(kNotchActionContainerPadding), child: child),
      );
    }

    final colors = context.semanticColors;
    final usesAccentHover = child is AppButton && (child as AppButton).variant == AppButtonVariant.ghost;
    final tooltip = child is AppIconButton ? (child as AppIconButton).tooltip : null;

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

          if (usesAccentHover) {
            return colors.accent;
          }

          return colors.foreground.withValues(alpha: 0.08);
        }),
        child: Padding(
          padding: const EdgeInsets.all(kNotchActionContainerPadding),
          child: _NotchedCardActionDisplay(action: child),
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
    final style = const FButtonStyleDelta.context()(
      context.theme.buttonStyles.resolve({_mapFButtonVariant(button.variant), context.platformVariant}).resolve({
        button.size.buttonSize,
        context.platformVariant,
      }),
    );
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

FButtonVariant _mapFButtonVariant(AppButtonVariant variant) => switch (variant) {
  AppButtonVariant.primary => FButtonVariant.primary,
  AppButtonVariant.secondary => FButtonVariant.secondary,
  AppButtonVariant.destructive => FButtonVariant.destructive,
  AppButtonVariant.outline => FButtonVariant.outline,
  AppButtonVariant.ghost => FButtonVariant.ghost,
};

VoidCallback? _actionOnPressed(Widget action) => switch (action) {
  AppIconButton(:final onPressed) => onPressed,
  AppButton(:final onPressed) => onPressed,
  _ => null,
};

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
