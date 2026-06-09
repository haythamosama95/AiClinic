import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../input/app_field_size.dart';

/// Semantic button variants mapped to forui [FButtonVariant] styles.
enum AppButtonVariant { primary, secondary, destructive, outline, ghost }

/// Application button wrapping [FButton] with loading and variant support.
class AppButton extends StatelessWidget {
  const AppButton({
    required this.label,
    this.onPressed,
    this.icon,
    this.isLoading = false,
    this.variant = AppButtonVariant.primary,
    this.size = AppFieldSize.md,
    this.expand = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final Widget? icon;
  final bool isLoading;
  final AppButtonVariant variant;
  final AppFieldSize size;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;

    return FButton(
      variant: _mapVariant(variant),
      size: size.buttonSize,
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      onPress: !enabled ? null : (isLoading ? () {} : onPressed),
      prefix: isLoading ? FCircularProgress(size: size.progressSize) : icon,
      child: Text(label),
    );
  }

  FButtonVariant _mapVariant(AppButtonVariant variant) => switch (variant) {
    AppButtonVariant.primary => FButtonVariant.primary,
    AppButtonVariant.secondary => FButtonVariant.secondary,
    AppButtonVariant.destructive => FButtonVariant.destructive,
    AppButtonVariant.outline => FButtonVariant.outline,
    AppButtonVariant.ghost => FButtonVariant.ghost,
  };
}
