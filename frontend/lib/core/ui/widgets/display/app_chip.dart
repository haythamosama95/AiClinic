import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/foundation.dart';

/// Size scale for [AppChip].
enum AppChipSize {
  /// Compact chip with caption text.
  sm,

  /// Default chip with body-sm text.
  md,
}

/// Compact descriptor for filters, tags, and multi-select values.
class AppChip extends StatefulWidget {
  const AppChip({
    required this.child,
    this.removable = false,
    this.onRemove,
    this.selectable = false,
    this.selected = false,
    this.onSelect,
    this.disabled = false,
    this.size = AppChipSize.md,
    this.onTap,
    super.key,
  });

  final Widget child;
  final bool removable;
  final VoidCallback? onRemove;
  final bool selectable;
  final bool selected;
  final VoidCallback? onSelect;
  final bool disabled;
  final AppChipSize size;
  final VoidCallback? onTap;

  @override
  State<AppChip> createState() => _AppChipState();
}

class _AppChipState extends State<AppChip> {
  bool _removing = false;

  void _handleRemove() {
    if (widget.disabled || widget.onRemove == null || _removing) return;
    final reduced = AppMotion.reduced(context);
    if (reduced) {
      widget.onRemove!();
      return;
    }
    setState(() => _removing = true);
    Future<void>.delayed(AppDurations.fast, () {
      if (mounted) widget.onRemove!();
    });
  }

  void _handleSelect() {
    if (widget.disabled) return;
    if (widget.selectable) widget.onSelect?.call();
    widget.onTap?.call();
  }

  String _removeLabel() {
    final child = widget.child;
    if (child is Text) {
      final text = child.data ?? child.textSpan?.toPlainText();
      if (text != null && text.isNotEmpty) return 'Remove $text';
    }
    return 'Remove filter';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final reduced = AppMotion.reduced(context);

    final textStyle = switch (widget.size) {
      AppChipSize.sm => typography.caption.copyWith(
        color: widget.selected
            ? colors.textPrimary
            : colors.textSecondary,
      ),
      AppChipSize.md => typography.bodySm.copyWith(
        color: widget.selected
            ? colors.textPrimary
            : colors.textSecondary,
      ),
    };

    final contentPadding = switch (widget.size) {
      AppChipSize.sm => const EdgeInsetsDirectional.symmetric(
        horizontal: AppSpacing.s1 + AppSpacing.s0_5,
        vertical: AppSpacing.s0_5,
      ),
      AppChipSize.md => const EdgeInsetsDirectional.symmetric(
        horizontal: AppSpacing.s2,
        vertical: AppSpacing.s0_5,
      ),
    };

    final removeSize = switch (widget.size) {
      AppChipSize.sm => AppSpacing.s5,
      AppChipSize.md => AppSpacing.s6,
    };

    final removeIconSize = AppSpacing.s3 + AppSpacing.s0_5;

    final borderRadius = AppRadii.smAll;

    Widget content = DecoratedBox(
      decoration: BoxDecoration(
        color: widget.selected
            ? colors.surfaceSelected
            : colors.surfaceDefault,
        border: Border.all(
          color: widget.selected
              ? colors.borderFocus
              : colors.borderDefault,
        ),
        borderRadius: borderRadius,
      ),
      child: Opacity(
        opacity: widget.disabled ? 0.6 : 1,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.selectable)
              AppPressable.builder(
                enabled: !widget.disabled,
                onTap: _handleSelect,
                borderRadius: borderRadius,
                semanticLabel: null,
                builder: (context, states, _) {
                  final hovered = states.contains(WidgetState.hovered);
                  return AnimatedContainer(
                    duration: reduced
                        ? AppDurations.instant
                        : AppDurations.instant,
                    curve: AppEasings.standard,
                    decoration: BoxDecoration(
                      color: !widget.selected && hovered
                          ? colors.surfaceHover
                          : Colors.transparent,
                      borderRadius: borderRadius,
                    ),
                    child: Padding(
                      padding: contentPadding,
                      child: DefaultTextStyle(
                        style: textStyle,
                        child: widget.child,
                      ),
                    ),
                  );
                },
              )
            else
              Padding(
                padding: contentPadding,
                child: DefaultTextStyle(
                  style: textStyle,
                  child: widget.child,
                ),
              ),
            if (widget.removable)
              AppPressable.builder(
                enabled: !widget.disabled,
                onTap: _handleRemove,
                semanticLabel: _removeLabel(),
                borderRadius: borderRadius,
                builder: (context, states, _) {
                  final hovered = states.contains(WidgetState.hovered);
                  return AnimatedContainer(
                    duration: reduced
                        ? AppDurations.instant
                        : AppDurations.instant,
                    curve: AppEasings.standard,
                    decoration: BoxDecoration(
                      color: hovered ? colors.surfaceHover : Colors.transparent,
                      borderRadius: borderRadius,
                    ),
                    child: SizedBox(
                      width: removeSize,
                      height: removeSize,
                      child: Center(
                        child: AppIcon(
                          icon: LucideIcons.x,
                          dimension: removeIconSize,
                          color: hovered
                              ? colors.iconDefault
                              : colors.iconMuted,
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );

    if (_removing && !reduced) {
      content = AnimatedOpacity(
        opacity: 0,
        duration: AppDurations.fast,
        curve: AppEasings.out,
        child: content,
      );
    }

    return content;
  }
}
