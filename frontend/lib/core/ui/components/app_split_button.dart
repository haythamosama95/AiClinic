import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/components/app_button.dart';
import 'package:ai_clinic/core/ui/components/app_pressable.dart';
import 'package:ai_clinic/core/ui/theme/app_color_primitives.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

/// Menu entry for [AppSplitButton].
@immutable
class SplitButtonMenuItem {
  const SplitButtonMenuItem({
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

typedef AppSplitButtonVariant = AppButtonVariant;
typedef AppSplitButtonSize = AppButtonSize;

/// Primary action button with a chevron dropdown for related secondary actions.
class AppSplitButton extends StatefulWidget {
  const AppSplitButton({
    required this.label,
    required this.items,
    this.onPrimaryAction,
    this.variant = AppButtonVariant.primary,
    this.size = AppButtonSize.md,
    this.disabled = false,
    this.loading = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPrimaryAction;
  final List<SplitButtonMenuItem> items;
  final AppButtonVariant variant;
  final AppButtonSize size;
  final bool disabled;
  final bool loading;

  @override
  State<AppSplitButton> createState() => _AppSplitButtonState();
}

class _AppSplitButtonState extends State<AppSplitButton> {
  final MenuController _menuController = MenuController();
  String? _selectedItemId;

  bool get _isDisabled => widget.disabled || widget.loading;

  String get _displayLabel {
    if (_selectedItemId != null) {
      final selected = widget.items.where((item) => item.id == _selectedItemId).firstOrNull;
      if (selected != null) return selected.label;
    }
    return widget.label;
  }

  void _handlePrimaryAction() {
    if (_selectedItemId != null) {
      final selected = widget.items.where((item) => item.id == _selectedItemId).firstOrNull;
      selected?.onSelect?.call();
      return;
    }
    widget.onPrimaryAction?.call();
  }

  @override
  void didUpdateWidget(covariant AppSplitButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_selectedItemId != null && !widget.items.any((item) => item.id == _selectedItemId)) {
      _selectedItemId = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final triggerStyle = _triggerStyle(colors, isDark);

    return Opacity(
      opacity: _isDisabled ? 0.6 : 1,
      child: IgnorePointer(
        ignoring: _isDisabled,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              AppButton(
                variant: widget.variant,
                size: widget.size,
                loading: widget.loading,
                disabled: widget.disabled,
                borderRadius: BorderRadius.zero,
                omitTrailingBorder: true,
                onPressed: _handlePrimaryAction,
                child: Text(_displayLabel),
              ),
              MenuAnchor(
                controller: _menuController,
                alignmentOffset: const Offset(0, AppSpacing.space1),
                style: MenuStyle(
                  elevation: const WidgetStatePropertyAll(0),
                  backgroundColor: WidgetStatePropertyAll(colors.surfaceRaised),
                  surfaceTintColor: WidgetStatePropertyAll(colors.surfaceRaised),
                  padding: const WidgetStatePropertyAll(EdgeInsets.all(AppSpacing.space1)),
                  shape: WidgetStatePropertyAll(
                    RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      side: BorderSide(color: colors.borderDefault),
                    ),
                  ),
                ),
                menuChildren: _buildMenuItems(context, colors, isDark),
                builder: (context, controller, child) {
                  return _SplitButtonTrigger(
                    label: _displayLabel,
                    isOpen: controller.isOpen,
                    size: widget.size,
                    style: triggerStyle,
                    onPressed: () {
                      if (controller.isOpen) {
                        controller.close();
                      } else {
                        controller.open();
                      }
                    },
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildMenuItems(BuildContext context, AppSemanticColors colors, bool isDark) {
    final items = <Widget>[];

    for (var index = 0; index < widget.items.length; index++) {
      final item = widget.items[index];
      final previous = index > 0 ? widget.items[index - 1] : null;

      if (previous != null && previous.destructive != item.destructive) {
        items.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.space1),
            child: Divider(height: 1, thickness: 1, color: colors.borderSubtle),
          ),
        );
      }

      items.add(
        MenuItemButton(
          onPressed: item.disabled
              ? null
              : () {
                  setState(() => _selectedItemId = item.id);
                  item.onSelect?.call();
                  _menuController.close();
                },
          style: ButtonStyle(
            foregroundColor: WidgetStateProperty.resolveWith((states) {
              if (item.disabled) {
                return colors.textPlaceholder;
              }
              if (item.destructive) {
                return colors.statusDangerFg;
              }
              return colors.textPrimary;
            }),
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              if (item.disabled) {
                return Colors.transparent;
              }
              if (states.contains(WidgetState.hovered) || states.contains(WidgetState.focused)) {
                return item.destructive
                    ? (isDark ? AppColorPrimitives.statusDangerSurfaceDark : AppColorPrimitives.red50)
                    : colors.surfaceHover;
              }
              return Colors.transparent;
            }),
            overlayColor: const WidgetStatePropertyAll(Colors.transparent),
            padding: const WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: AppSpacing.space2, vertical: AppSpacing.space1 + 2),
            ),
            shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md))),
            textStyle: WidgetStatePropertyAll(AppTypography.body(context)),
          ),
          child: Text(item.label),
        ),
      );
    }

    return items;
  }

  _TriggerStyle _triggerStyle(AppSemanticColors colors, bool isDark) {
    if (_isDisabled) {
      final disabledFg = isDark ? AppColorPrimitives.textDisabledDark : AppColorPrimitives.neutral400;
      final disabledBg = isDark ? AppColorPrimitives.actionDisabledBgDark : AppColorPrimitives.neutral100;
      return _TriggerStyle(background: disabledBg, foreground: disabledFg, hover: disabledBg, border: BorderSide.none);
    }

    return switch (widget.variant) {
      AppButtonVariant.primary => _TriggerStyle(
        background: colors.actionPrimary,
        foreground: colors.actionPrimaryFg,
        hover: colors.actionPrimaryHover,
        border: BorderSide(color: colors.actionPrimaryHover),
      ),
      AppButtonVariant.secondary => _TriggerStyle(
        background: colors.actionSecondary,
        foreground: colors.actionSecondaryFg,
        hover: colors.surfaceHover,
        border: BorderSide(color: colors.borderDefault),
      ),
      AppButtonVariant.ghost => _TriggerStyle(
        background: Colors.transparent,
        foreground: colors.textPrimary,
        hover: colors.actionSubtleHover,
        border: BorderSide(color: colors.borderDefault),
      ),
      AppButtonVariant.danger => _TriggerStyle(
        background: colors.actionDanger,
        foreground: colors.actionDangerFg,
        hover: colors.actionDangerHover,
        border: BorderSide(color: colors.actionDangerHover),
      ),
      AppButtonVariant.ai => _TriggerStyle(
        background: colors.actionAi,
        foreground: colors.actionAiFg,
        hover: colors.actionAiHover,
        border: BorderSide(color: colors.actionAiHover),
      ),
      AppButtonVariant.link => _TriggerStyle(
        background: Colors.transparent,
        foreground: colors.textLink,
        hover: colors.actionSubtleHover,
        border: BorderSide.none,
      ),
    };
  }
}

class _TriggerStyle {
  const _TriggerStyle({required this.background, required this.foreground, required this.hover, required this.border});

  final Color background;
  final Color foreground;
  final Color hover;
  final BorderSide border;

  Color resolve({required bool hovered, required bool pressed}) {
    if (pressed) return hover;
    if (hovered) return hover;
    return background;
  }
}

class _SplitButtonTrigger extends StatefulWidget {
  const _SplitButtonTrigger({
    required this.label,
    required this.isOpen,
    required this.size,
    required this.style,
    required this.onPressed,
  });

  final String label;
  final bool isOpen;
  final AppButtonSize size;
  final _TriggerStyle style;
  final VoidCallback onPressed;

  @override
  State<_SplitButtonTrigger> createState() => _SplitButtonTriggerState();
}

class _SplitButtonTriggerState extends State<_SplitButtonTrigger> {
  var _hovered = false;
  var _pressed = false;

  double get _dimension => switch (widget.size) {
    AppButtonSize.sm => 28.0,
    AppButtonSize.md => 36.0,
    AppButtonSize.lg => 44.0,
  };

  double get _chevronSize => switch (widget.size) {
    AppButtonSize.sm => 14.0,
    AppButtonSize.md => 16.0,
    AppButtonSize.lg => 18.0,
  };

  @override
  Widget build(BuildContext context) {
    final background = widget.style.resolve(hovered: _hovered, pressed: _pressed);

    return Semantics(
      button: true,
      label: '${widget.label} — more options',
      expanded: widget.isOpen,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() {
          _hovered = false;
          _pressed = false;
        }),
        cursor: SystemMouseCursors.click,
        child: AppPressable(
          onPressed: widget.onPressed,
          onPressedChanged: (pressed) => setState(() => _pressed = pressed),
          child: Container(
            width: _dimension,
            height: _dimension,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: background,
              border: Border(top: widget.style.border, bottom: widget.style.border, right: widget.style.border),
            ),
            child: Icon(Icons.keyboard_arrow_down, size: _chevronSize, color: widget.style.foreground),
          ),
        ),
      ),
    );
  }
}
