import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/foundation.dart';
import 'package:ai_clinic/core/ui/widgets/navigation/app_dropdown_menu.dart';
import 'package:ai_clinic/core/ui/widgets/overlays/app_popover.dart';

import '_button_shared.dart';
import 'app_spinner.dart';

/// Menu item for [AppSplitButton]'s dropdown menu.
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

/// Primary action with a chevron segment that opens related secondary actions.
class AppSplitButton extends StatefulWidget {
  const AppSplitButton({
    required this.label,
    required this.menuItems,
    this.onPressed,
    this.onMenuRequested,
    this.variant = AppButtonVariant.primary,
    this.size = AppButtonSize.md,
    this.loading = false,
    this.disabled = false,
    super.key,
  });

  final String label;
  final List<AppSplitButtonMenuItem> menuItems;
  final VoidCallback? onPressed;
  final VoidCallback? onMenuRequested;
  final AppButtonVariant variant;
  final AppButtonSize size;
  final bool loading;
  final bool disabled;

  @override
  State<AppSplitButton> createState() => _AppSplitButtonState();
}

class _AppSplitButtonState extends State<AppSplitButton> {
  late final AppPopoverController _menuController;

  @override
  void initState() {
    super.initState();
    _menuController = AppPopoverController();
    _menuController.addListener(_handleMenuOpenChange);
  }

  @override
  void dispose() {
    _menuController.removeListener(_handleMenuOpenChange);
    _menuController.dispose();
    super.dispose();
  }

  void _handleMenuOpenChange() {
    setState(() {});
  }

  bool get _isDisabled => widget.disabled || widget.loading;

  double get _segmentHeight => AppButtonShared.height(widget.size);

  double get _chevronSegmentWidth => _segmentHeight;

  double get _chevronIconDimension => switch (widget.size) {
    AppButtonSize.sm => AppIconSize.sm.value - AppSpacing.s0_5,
    AppButtonSize.md => AppIconSize.sm.value,
    AppButtonSize.lg => AppIconSize.md.value - AppSpacing.s0_5,
  };

  BorderRadius _primaryRadius(BuildContext context) =>
      const BorderRadiusDirectional.only(
        topStart: Radius.circular(AppRadii.md),
        bottomStart: Radius.circular(AppRadii.md),
      ).resolve(Directionality.of(context));

  BorderRadius _chevronRadius(BuildContext context) =>
      const BorderRadiusDirectional.only(
        topEnd: Radius.circular(AppRadii.md),
        bottomEnd: Radius.circular(AppRadii.md),
      ).resolve(Directionality.of(context));

  void _handleChevronPressed(VoidCallback toggle) {
    if (_isDisabled) return;
    if (widget.onMenuRequested != null) {
      widget.onMenuRequested!();
      return;
    }
    toggle();
  }

  Color _chevronBackground(AppColors colors, Set<WidgetState> states) {
    if (_isDisabled) return colors.actionDisabledBg;

    if (states.contains(WidgetState.pressed)) {
      return switch (widget.variant) {
        AppButtonVariant.primary => colors.actionPrimaryActive,
        AppButtonVariant.secondary => colors.surfaceMuted,
        AppButtonVariant.ghost => colors.surfaceMuted,
        AppButtonVariant.danger => colors.actionDangerActive,
        AppButtonVariant.ai => colors.actionAi,
        AppButtonVariant.link => Colors.transparent,
      };
    }

    if (states.contains(WidgetState.hovered)) {
      return switch (widget.variant) {
        AppButtonVariant.primary => colors.actionPrimaryHover,
        AppButtonVariant.secondary => colors.surfaceHover,
        AppButtonVariant.ghost => colors.actionSubtleHover,
        AppButtonVariant.danger => colors.actionDangerHover,
        AppButtonVariant.ai => colors.actionAiHover,
        AppButtonVariant.link => Colors.transparent,
      };
    }

    return AppButtonShared.background(
      colors,
      widget.variant,
      const {},
      disabled: false,
    );
  }

  Color? _chevronBorderColor(AppColors colors) {
    if (_isDisabled) return null;
    return switch (widget.variant) {
      AppButtonVariant.primary => colors.actionPrimaryHover,
      AppButtonVariant.secondary => colors.borderDefault,
      AppButtonVariant.ghost => colors.borderDefault,
      AppButtonVariant.danger => colors.actionDangerHover,
      AppButtonVariant.ai => colors.actionAiHover,
      AppButtonVariant.link => null,
    };
  }

  Widget _buildChevronPressable(
    BuildContext context, {
    required AppColors colors,
    required Color foreground,
    required String menuSemanticLabel,
    VoidCallback? onTap,
  }) {
    return AppPressable.builder(
      enabled: !_isDisabled,
      onTap: onTap,
      semanticLabel: menuSemanticLabel,
      focusRingVariant: AppButtonShared.focusRingVariant(widget.variant),
      borderRadius: _chevronRadius(context),
      builder: (context, states, _) {
        final borderColor = _chevronBorderColor(colors) ?? Colors.transparent;
        return AnimatedContainer(
          duration: AppDurations.instant,
          curve: AppEasings.standard,
          width: _chevronSegmentWidth,
          height: _segmentHeight,
          decoration: BoxDecoration(
            color: _chevronBackground(colors, states),
            borderRadius: _chevronRadius(context),
            border: BorderDirectional(
              top: BorderSide(color: borderColor),
              bottom: BorderSide(color: borderColor),
              end: BorderSide(color: borderColor),
            ),
          ),
          alignment: Alignment.center,
          child: AppIcon(
            icon: LucideIcons.chevronDown,
            dimension: _chevronIconDimension,
            color: foreground,
            mirrorInRtl: true,
          ),
        );
      },
    );
  }

  List<Widget> _buildMenuChildren() {
    final children = <Widget>[];
    var order = 0;

    for (var index = 0; index < widget.menuItems.length; index++) {
      final item = widget.menuItems[index];
      final previous = index > 0 ? widget.menuItems[index - 1] : null;
      if (previous != null && previous.destructive != item.destructive) {
        children.add(const AppDropdownMenuSeparator());
      }

      children.add(
        AppDropdownMenuItem(
          key: ValueKey<String>(item.id),
          label: item.label,
          destructive: item.destructive,
          disabled: item.disabled,
          order: order++,
          onSelected: item.onSelect,
        ),
      );
    }

    return children;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final foreground = AppButtonShared.foreground(
      colors,
      widget.variant,
      const {},
      disabled: _isDisabled,
    );
    final menuSemanticLabel = '${widget.label} — more options';

    Widget chevronSegment = _buildChevronPressable(
      context,
      colors: colors,
      foreground: foreground,
      menuSemanticLabel: menuSemanticLabel,
      onTap: widget.onMenuRequested != null
          ? () => _handleChevronPressed(() {})
          : null,
    );

    if (widget.onMenuRequested == null && widget.menuItems.isNotEmpty) {
      chevronSegment = AppDropdownMenu(
        controller: _menuController,
        align: AppDropdownMenuAlign.end,
        trigger: (ctx, show, hide, toggle) => _buildChevronPressable(
          ctx,
          colors: colors,
          foreground: foreground,
          menuSemanticLabel: menuSemanticLabel,
          onTap: () => _handleChevronPressed(toggle),
        ),
        children: _buildMenuChildren(),
      );
    }

    chevronSegment = Semantics(
      button: true,
      enabled: !_isDisabled,
      label: menuSemanticLabel,
      expanded: _menuController.isOpen,
      child: chevronSegment,
    );

    return Opacity(
      opacity: _isDisabled ? 0.6 : 1,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PrimarySegment(
            label: widget.label,
            variant: widget.variant,
            size: widget.size,
            loading: widget.loading,
            disabled: _isDisabled,
            borderRadius: _primaryRadius(context),
            onPressed: widget.onPressed,
          ),
          chevronSegment,
        ],
      ),
    );
  }
}

class _PrimarySegment extends StatelessWidget {
  const _PrimarySegment({
    required this.label,
    required this.variant,
    required this.size,
    required this.loading,
    required this.disabled,
    required this.borderRadius,
    this.onPressed,
  });

  final String label;
  final AppButtonVariant variant;
  final AppButtonSize size;
  final bool loading;
  final bool disabled;
  final BorderRadius borderRadius;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final height = AppButtonShared.height(size);
    final spinnerSize = size == AppButtonSize.lg ? AppSpinnerSize.md : AppSpinnerSize.sm;
    final textStyle = AppButtonShared.textStyle(context, size);

    return AppPressable.builder(
      enabled: !disabled,
      onTap: onPressed,
      focusRingVariant: AppButtonShared.focusRingVariant(variant),
      borderRadius: borderRadius,
      builder: (context, states, _) {
        final background = AppButtonShared.background(
          colors,
          variant,
          states,
          disabled: disabled,
        );
        final foreground = AppButtonShared.foreground(
          colors,
          variant,
          states,
          disabled: disabled,
        );
        final borderColor = AppButtonShared.borderColor(
          colors,
          variant,
          disabled: disabled,
        );

        return AnimatedContainer(
          duration: AppDurations.instant,
          curve: AppEasings.standard,
          height: height,
          constraints: BoxConstraints(minWidth: AppButtonShared.minWidth(size)),
          padding: AppButtonShared.padding(size, variant),
          decoration: AppButtonShared.decoration(
            background: background,
            borderRadius: borderRadius,
            borderColor: borderColor,
            colors: colors,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (loading) ...[
                AppSpinner(size: spinnerSize, color: foreground),
                const SizedBox(width: AppSpacing.s2),
              ],
              Text(
                label,
                style: textStyle.copyWith(color: foreground),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        );
      },
    );
  }
}
