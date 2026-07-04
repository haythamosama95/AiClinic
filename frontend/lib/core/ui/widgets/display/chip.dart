import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/motion/app_motion.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/theme_context_extensions.dart';

/// Compact filter or tag chip with optional selection and remove control.
class AppChip extends StatelessWidget {
  const AppChip({
    super.key,
    required this.label,
    this.selectable = false,
    this.selected = false,
    this.onSelected,
    this.removable = false,
    this.onDeleted,
    this.enabled = true,
    this.onTap,
  });

  final Widget label;
  final bool selectable;
  final bool selected;
  final VoidCallback? onSelected;
  final bool removable;
  final VoidCallback? onDeleted;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    final borderColor = selected ? colors.borderFocus : colors.borderDefault;
    final backgroundColor = selected
        ? colors.surfaceSelected
        : colors.surfaceDefault;
    final textColor = selected ? colors.textPrimary : colors.textSecondary;

    Widget content = DefaultTextStyle(
      style: typography.bodySm.copyWith(color: textColor),
      child: IconTheme(
        data: IconThemeData(size: 14, color: textColor),
        child: label,
      ),
    );

    if (selectable) {
      content = Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: enabled
              ? () {
                  onSelected?.call();
                  onTap?.call();
                }
              : null,
          borderRadius: AppRadius.smAll,
          hoverColor: !selected ? colors.surfaceHover : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s2,
              vertical: AppSpacing.s0_5,
            ),
            child: content,
          ),
        ),
      );
    } else {
      content = Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s2,
          vertical: AppSpacing.s0_5,
        ),
        child: content,
      );
    }

    return Opacity(
      opacity: enabled ? 1 : 0.6,
      child: Container(
        constraints: const BoxConstraints(minHeight: 24),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: AppRadius.smAll,
          border: Border.all(color: borderColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selectable)
              Semantics(
                button: true,
                enabled: enabled,
                selected: selected,
                child: content,
              )
            else
              content,
            if (removable)
              _RemoveButton(
                enabled: enabled,
                label: _labelText(label),
                onDeleted: onDeleted,
              ),
          ],
        ),
      ),
    );
  }

  static String _labelText(Widget label) {
    if (label is Text) return label.data ?? 'filter';
    return 'filter';
  }
}

class _RemoveButton extends StatefulWidget {
  const _RemoveButton({
    required this.enabled,
    required this.label,
    this.onDeleted,
  });

  final bool enabled;
  final String label;
  final VoidCallback? onDeleted;

  @override
  State<_RemoveButton> createState() => _RemoveButtonState();
}

class _RemoveButtonState extends State<_RemoveButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Semantics(
      button: true,
      enabled: widget.enabled,
      label: 'Remove ${widget.label}',
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: widget.enabled ? widget.onDeleted : null,
            borderRadius: AppRadius.smAll,
            child: AnimatedContainer(
              duration: AppDurations.instant,
              width: 24,
              height: 24,
              alignment: Alignment.center,
              color: _hovered ? colors.surfaceHover : Colors.transparent,
              child: Icon(
                Icons.close,
                size: 14,
                color: _hovered ? colors.iconDefault : colors.iconMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
