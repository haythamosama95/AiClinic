import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/components/app_pressable.dart';
import 'package:ai_clinic/core/ui/motion/app_motion.dart';
import 'package:ai_clinic/core/ui/theme/app_color_primitives.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

/// Plain, selectable, or removable chip (web `Chip`).
class AppChip extends StatefulWidget {
  const AppChip({
    required this.child,
    this.removable = false,
    this.onRemove,
    this.selectable = false,
    this.selected = false,
    this.onSelect,
    this.onPressed,
    this.disabled = false,
    this.semanticsLabel,
    super.key,
  });

  final Widget child;
  final bool removable;
  final VoidCallback? onRemove;
  final bool selectable;
  final bool selected;
  final VoidCallback? onSelect;
  final VoidCallback? onPressed;
  final bool disabled;
  final String? semanticsLabel;

  @override
  State<AppChip> createState() => _AppChipState();
}

class _AppChipState extends State<AppChip> {
  var _bodyHovered = false;
  var _removeHovered = false;

  bool get _isDisabled => widget.disabled;

  Color _focusBorderColor(Brightness brightness) {
    return brightness == Brightness.dark ? AppColorPrimitives.teal400 : AppColorPrimitives.teal500;
  }

  String get _removeSemanticsLabel {
    if (widget.semanticsLabel != null) {
      return 'Remove ${widget.semanticsLabel}';
    }
    if (widget.child case final Text text when text.data != null) {
      return 'Remove ${text.data}';
    }
    return 'Remove filter';
  }

  void _handleBodyPress() {
    if (_isDisabled) return;
    if (widget.selectable) {
      widget.onSelect?.call();
    }
    widget.onPressed?.call();
  }

  void _handleRemove() {
    if (_isDisabled) return;
    widget.onRemove?.call();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final brightness = Theme.of(context).brightness;
    final borderColor = widget.selected ? _focusBorderColor(brightness) : colors.borderDefault;
    final background = widget.selected ? colors.surfaceSelected : colors.surfaceDefault;
    final foreground = widget.selected ? colors.textPrimary : colors.textSecondary;

    return UnconstrainedBox(
      constrainedAxis: Axis.vertical,
      alignment: AlignmentDirectional.centerStart,
      clipBehavior: Clip.none,
      child: Opacity(
        opacity: _isDisabled ? 0.6 : 1,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.selectable)
                _ChipBody(
                  hovered: _bodyHovered,
                  selected: widget.selected,
                  disabled: _isDisabled,
                  foreground: foreground,
                  hoverColor: colors.surfaceHover,
                  onHoverChanged: (hovered) => setState(() => _bodyHovered = hovered),
                  onPressed: _handleBodyPress,
                  selectedSemantics: widget.selected,
                  child: widget.child,
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.space2,
                    vertical: AppSpacing.space05,
                  ),
                  child: DefaultTextStyle(
                    style: AppTypography.bodySm(context).copyWith(color: foreground),
                    child: IconTheme(
                      data: IconThemeData(size: 14, color: colors.iconMuted),
                      child: widget.child,
                    ),
                  ),
                ),
              if (widget.removable)
                _ChipRemoveButton(
                  hovered: _removeHovered,
                  disabled: _isDisabled,
                  semanticsLabel: _removeSemanticsLabel,
                  colors: colors,
                  onHoverChanged: (hovered) => setState(() => _removeHovered = hovered),
                  onPressed: _handleRemove,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChipBody extends StatelessWidget {
  const _ChipBody({
    required this.hovered,
    required this.selected,
    required this.disabled,
    required this.foreground,
    required this.hoverColor,
    required this.onHoverChanged,
    required this.onPressed,
    required this.selectedSemantics,
    required this.child,
  });

  final bool hovered;
  final bool selected;
  final bool disabled;
  final Color foreground;
  final Color hoverColor;
  final ValueChanged<bool> onHoverChanged;
  final VoidCallback onPressed;
  final bool selectedSemantics;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final background = !selected && hovered ? hoverColor : Colors.transparent;

    return Semantics(
      button: true,
      selected: selectedSemantics,
      enabled: !disabled,
      child: MouseRegion(
        onEnter: disabled ? null : (_) => onHoverChanged(true),
        onExit: disabled ? null : (_) => onHoverChanged(false),
        cursor: disabled ? SystemMouseCursors.basic : SystemMouseCursors.click,
        child: AppPressable(
          enabled: !disabled,
          onPressed: onPressed,
          child: AnimatedContainer(
            duration: AppMotion.instant,
            curve: AppMotion.standardCurve,
            constraints: const BoxConstraints(minHeight: 24),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.space2,
              vertical: AppSpacing.space05,
            ),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: DefaultTextStyle(
              style: AppTypography.bodySm(context).copyWith(color: foreground),
              child: IconTheme(
                data: IconThemeData(size: 14, color: foreground),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChipRemoveButton extends StatelessWidget {
  const _ChipRemoveButton({
    required this.hovered,
    required this.disabled,
    required this.semanticsLabel,
    required this.colors,
    required this.onHoverChanged,
    required this.onPressed,
  });

  final bool hovered;
  final bool disabled;
  final String semanticsLabel;
  final AppSemanticColors colors;
  final ValueChanged<bool> onHoverChanged;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final iconColor = hovered ? colors.iconDefault : colors.iconMuted;

    return Semantics(
      button: true,
      label: semanticsLabel,
      enabled: !disabled,
      child: MouseRegion(
        onEnter: disabled ? null : (_) => onHoverChanged(true),
        onExit: disabled ? null : (_) => onHoverChanged(false),
        cursor: disabled ? SystemMouseCursors.basic : SystemMouseCursors.click,
        child: AppPressable(
          enabled: !disabled,
          onPressed: onPressed,
          child: AnimatedContainer(
            duration: AppMotion.instant,
            curve: AppMotion.standardCurve,
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: hovered ? colors.surfaceHover : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(Icons.close, size: 14, color: iconColor),
          ),
        ),
      ),
    );
  }
}
