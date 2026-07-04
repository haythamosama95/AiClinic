import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/foundation.dart';

import '_button_shared.dart';
import 'app_spinner.dart';

export '_button_shared.dart' show AppIconButtonSize, AppIconButtonVariant;

/// Compact square action for toolbars and dense layouts.
class AppIconButton extends StatelessWidget {
  const AppIconButton({
    required this.icon,
    required this.semanticLabel,
    this.onPressed,
    this.variant = AppIconButtonVariant.ghost,
    this.size = AppIconButtonSize.md,
    this.tooltip,
    this.loading = false,
    this.disabled = false,
    this.error = false,
    super.key,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback? onPressed;
  final AppIconButtonVariant variant;
  final AppIconButtonSize size;
  final String? tooltip;
  final bool loading;
  final bool disabled;
  final bool error;

  bool get _isDisabled => disabled || loading;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final dimension = AppButtonShared.iconButtonDimension(size);
    final iconDimension = AppButtonShared.iconButtonIconDimension(size);
    final borderRadius = AppRadii.mdAll;
    final spinnerSize =
        size == AppIconButtonSize.lg ? AppSpinnerSize.md : AppSpinnerSize.sm;

    return AppPressable.builder(
      enabled: !_isDisabled,
      onTap: onPressed,
      semanticLabel: semanticLabel,
      tooltip: _isDisabled ? null : (tooltip ?? semanticLabel),
      focusRingVariant: AppButtonShared.iconButtonFocusRingVariant(variant),
      borderRadius: borderRadius,
      builder: (context, states, _) {
        final background = AppButtonShared.iconButtonBackground(
          colors,
          variant,
          states,
          disabled: _isDisabled,
        );
        final foreground = AppButtonShared.iconButtonForeground(
          colors,
          variant,
          states,
          disabled: _isDisabled,
        );
        final borderColor = AppButtonShared.iconButtonBorderColor(
          colors,
          variant,
          disabled: _isDisabled,
        );

        return AnimatedContainer(
          duration: AppDurations.instant,
          curve: AppEasings.standard,
          width: dimension,
          height: dimension,
          decoration: AppButtonShared.decoration(
            background: background,
            borderRadius: borderRadius,
            borderColor: borderColor,
            error: error && !_isDisabled,
            colors: colors,
          ),
          alignment: Alignment.center,
          child: loading
              ? AppSpinner(size: spinnerSize, color: foreground)
              : AppIcon(
                  icon: icon,
                  dimension: iconDimension,
                  color: foreground,
                ),
        );
      },
    );
  }
}
