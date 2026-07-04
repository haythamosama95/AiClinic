import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:ai_clinic/core/ui/motion/app_motion.dart';
import 'package:ai_clinic/core/ui/theme/app_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
import 'package:ai_clinic/core/ui/theme/theme_context_extensions.dart';
import 'package:ai_clinic/core/ui/widgets/actions/button.dart';

@immutable
class AppSplitButtonMenuItem {
  const AppSplitButtonMenuItem({
    required this.id,
    required this.label,
    this.onSelect,
    this.disabled = false,
    this.destructive = false,
  });

  final String id;
  final String label;
  final VoidCallback? onSelect;
  final bool disabled;
  final bool destructive;
}

/// Primary action with adjacent menu trigger, matching the web `SplitButton`.
class AppSplitButton extends StatefulWidget {
  const AppSplitButton({
    super.key,
    required this.label,
    required this.items,
    this.onPrimaryAction,
    this.variant = AppButtonVariant.primary,
    this.size = AppButtonSize.md,
    this.disabled = false,
    this.loading = false,
  });

  final String label;
  final List<AppSplitButtonMenuItem> items;
  final VoidCallback? onPrimaryAction;
  final AppButtonVariant variant;
  final AppButtonSize size;
  final bool disabled;
  final bool loading;

  bool get isDisabled => disabled || loading;

  @override
  State<AppSplitButton> createState() => _AppSplitButtonState();
}

class _AppSplitButtonState extends State<AppSplitButton> {
  final LayerLink _menuLink = LayerLink();
  OverlayEntry? _overlayEntry;
  bool _menuOpen = false;
  bool _triggerHovered = false;
  bool _triggerPressed = false;
  bool _triggerFocused = false;
  final FocusNode _triggerFocusNode = FocusNode();

  @override
  void dispose() {
    _removeOverlay();
    _triggerFocusNode.dispose();
    super.dispose();
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    if (_menuOpen) {
      setState(() => _menuOpen = false);
    }
  }

  void _toggleMenu() {
    if (widget.isDisabled) return;
    if (_menuOpen) {
      _removeOverlay();
    } else {
      _showOverlay();
    }
  }

  void _showOverlay() {
    final overlay = Overlay.of(context);
    final colors = context.colors;
    final typography = context.typography;
    final elevation = context.elevation;

    _overlayEntry = OverlayEntry(
      builder: (overlayContext) {
        final isRtl = Directionality.of(overlayContext) == TextDirection.rtl;
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _removeOverlay,
              ),
            ),
            CompositedTransformFollower(
              link: _menuLink,
              showWhenUnlinked: false,
              targetAnchor: isRtl
                  ? Alignment.bottomLeft
                  : Alignment.bottomRight,
              followerAnchor: isRtl ? Alignment.topLeft : Alignment.topRight,
              offset: const Offset(0, AppSpacing.s1),
              child: _SplitButtonMenuPanel(
                items: widget.items,
                colors: colors,
                typography: typography,
                elevation: elevation.level2,
                onItemSelected: (item) {
                  item.onSelect?.call();
                  _removeOverlay();
                },
              ),
            ),
          ],
        );
      },
    );

    overlay.insert(_overlayEntry!);
    setState(() => _menuOpen = true);
  }

  double get _triggerSize => switch (widget.size) {
    AppButtonSize.sm => 28,
    AppButtonSize.md => 36,
    AppButtonSize.lg => 44,
  };

  double get _chevronSize => switch (widget.size) {
    AppButtonSize.sm => 14,
    AppButtonSize.md => 16,
    AppButtonSize.lg => 18,
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final palette = AppButtonColors.resolve(
      colors: colors,
      variant: widget.variant,
      disabled: widget.isDisabled,
    );
    final reducedMotion = AppMotion.isReducedMotion(context);
    final borderRadius = AppRadius.mdAll;
    final leadingCorners = borderRadius.resolve(Directionality.of(context));
    final trailingCorners = BorderRadius.only(
      topLeft: Radius.zero,
      bottomLeft: Radius.zero,
      topRight: leadingCorners.topRight,
      bottomRight: leadingCorners.bottomRight,
    );

    Color background = palette.background;
    if (!widget.isDisabled) {
      if (_triggerPressed) {
        background = palette.activeBackground;
      } else if (_triggerHovered) {
        background = palette.hoverBackground;
      }
    }

    final ringColor = _triggerFocused ? palette.focusRing : Colors.transparent;

    final trigger = CompositedTransformTarget(
      link: _menuLink,
      child: Semantics(
        button: true,
        label: '${widget.label} — more options',
        enabled: !widget.isDisabled,
        expanded: _menuOpen,
        child: Focus(
          focusNode: _triggerFocusNode,
          onFocusChange: (focused) => setState(() => _triggerFocused = focused),
          onKeyEvent: (_, event) {
            if (widget.isDisabled) return KeyEventResult.ignored;
            if (event is KeyDownEvent &&
                (event.logicalKey == LogicalKeyboardKey.enter ||
                    event.logicalKey == LogicalKeyboardKey.space ||
                    event.logicalKey == LogicalKeyboardKey.arrowDown)) {
              _toggleMenu();
              return KeyEventResult.handled;
            }
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.escape &&
                _menuOpen) {
              _removeOverlay();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: MouseRegion(
            cursor: widget.isDisabled
                ? SystemMouseCursors.basic
                : SystemMouseCursors.click,
            onEnter: (_) => setState(() => _triggerHovered = true),
            onExit: (_) => setState(() {
              _triggerHovered = false;
              _triggerPressed = false;
            }),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: widget.isDisabled
                  ? null
                  : (_) => setState(() => _triggerPressed = true),
              onTapUp: widget.isDisabled
                  ? null
                  : (_) => setState(() => _triggerPressed = false),
              onTapCancel: widget.isDisabled
                  ? null
                  : () => setState(() => _triggerPressed = false),
              onTap: widget.isDisabled ? null : _toggleMenu,
              child: Container(
                padding: ringColor == Colors.transparent
                    ? EdgeInsets.zero
                    : const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  borderRadius: trailingCorners,
                  border: ringColor == Colors.transparent
                      ? null
                      : Border.all(color: ringColor, width: 2),
                ),
                child: AnimatedScale(
                  scale: _triggerPressed && !widget.isDisabled && !reducedMotion
                      ? AppMotion.buttonPressScale
                      : 1,
                  duration: AppDurations.instant,
                  curve: AppCurves.standard,
                  child: AnimatedContainer(
                    duration: AppDurations.instant,
                    width: _triggerSize,
                    height: _triggerSize,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: background,
                      border: BorderDirectional(
                        top: BorderSide(
                          color: palette.border ?? palette.hoverBackground,
                        ),
                        bottom: BorderSide(
                          color: palette.border ?? palette.hoverBackground,
                        ),
                        end: BorderSide(
                          color: palette.border ?? palette.hoverBackground,
                        ),
                      ),
                      borderRadius: trailingCorners,
                    ),
                    child: Icon(
                      Icons.keyboard_arrow_down,
                      size: _chevronSize,
                      color: palette.foreground,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    return Opacity(
      opacity: widget.isDisabled ? 0.6 : 1,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppButton(
            onPressed: widget.isDisabled ? null : widget.onPrimaryAction,
            variant: widget.variant,
            size: widget.size,
            loading: widget.loading,
            disabled: widget.disabled,
            clipLeadingRadius: true,
            clipTrailingRadius: false,
            borderRadius: BorderRadius.only(
              topLeft: leadingCorners.topLeft,
              bottomLeft: leadingCorners.bottomLeft,
              topRight: Radius.zero,
              bottomRight: Radius.zero,
            ),
            child: Text(widget.label),
          ),
          trigger,
        ],
      ),
    );
  }
}

class _SplitButtonMenuPanel extends StatelessWidget {
  const _SplitButtonMenuPanel({
    required this.items,
    required this.colors,
    required this.typography,
    required this.elevation,
    required this.onItemSelected,
  });

  final List<AppSplitButtonMenuItem> items;
  final AppColors colors;
  final AppTypography typography;
  final List<BoxShadow> elevation;
  final ValueChanged<AppSplitButtonMenuItem> onItemSelected;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: colors.surfaceRaised,
      elevation: 0,
      shadowColor: Colors.transparent,
      borderRadius: AppRadius.lgAll,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: AppRadius.lgAll,
          border: Border.all(color: colors.borderDefault),
          boxShadow: elevation,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 160),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.s1),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0 && items[i - 1].destructive != items[i].destructive)
                    Divider(height: AppSpacing.s2, color: colors.borderSubtle),
                  _SplitButtonMenuRow(
                    item: items[i],
                    typography: typography,
                    colors: colors,
                    onSelected: () => onItemSelected(items[i]),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SplitButtonMenuRow extends StatefulWidget {
  const _SplitButtonMenuRow({
    required this.item,
    required this.typography,
    required this.colors,
    required this.onSelected,
  });

  final AppSplitButtonMenuItem item;
  final AppTypography typography;
  final AppColors colors;
  final VoidCallback onSelected;

  @override
  State<_SplitButtonMenuRow> createState() => _SplitButtonMenuRowState();
}

class _SplitButtonMenuRowState extends State<_SplitButtonMenuRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final colors = widget.colors;
    final foreground = item.disabled
        ? colors.textDisabled
        : item.destructive
        ? colors.statusDangerFg
        : colors.textPrimary;
    final background = item.disabled
        ? Colors.transparent
        : _hovered
        ? (item.destructive ? colors.statusDangerSurface : colors.surfaceHover)
        : Colors.transparent;

    return MouseRegion(
      onEnter: item.disabled ? null : (_) => setState(() => _hovered = true),
      onExit: item.disabled ? null : (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: item.disabled ? null : widget.onSelected,
        child: AnimatedContainer(
          duration: AppDurations.instant,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s2,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            color: background,
            borderRadius: AppRadius.mdAll,
          ),
          child: Text(
            item.label,
            style: widget.typography.body.copyWith(color: foreground),
          ),
        ),
      ),
    );
  }
}
